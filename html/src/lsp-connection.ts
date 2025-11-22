/**
 * LSP WebSocket Connection for KLighD Diagrams
 */

import { Container } from 'inversify';
import { ActionMessage } from 'sprotty-protocol';
import { listen } from 'vscode-ws-jsonrpc';
import * as rpc from 'vscode-jsonrpc/browser';
import { IActionDispatcher, TYPES } from 'sprotty';
import { Connection, NotificationType } from '@kieler/klighd-core';

export class LFDiagramConnection implements Connection {
    private connection: rpc.MessageConnection | null = null;
    private webSocket: WebSocket | null = null;
    private container: Container;
    private requestId: number = 1; // Counter for request IDs
    private workspaceRoot: string = '';
    private fileUri: string;
    private messageHandler: ((message: ActionMessage) => void) | null = null;
    private readyPromise: Promise<void>;
    private readyResolve: (() => void) | null = null;

    constructor(container: Container, fileUri: string) {
        this.container = container;
        this.fileUri = fileUri;
        this.readyPromise = new Promise((resolve) => {
            this.readyResolve = resolve;
        });
    }

    // KLighD Connection interface methods
    sendMessage(message: ActionMessage): void {
        console.log('KLighD sendMessage:', message);
        if (this.connection && message.action) {
            this.connection.sendNotification('diagram/dispatch', message);
        }
    }

    sendNotification<T extends Record<string, unknown>>(type: NotificationType, payload: T): void {
        console.log('KLighD sendNotification:', type, payload);
        if (this.connection) {
            this.connection.sendNotification(type.toString(), payload);
        }
    }

    onMessageReceived(handler: (message: ActionMessage) => void): void {
        console.log('KLighD onMessageReceived: handler registered');
        this.messageHandler = handler;
    }

    onReady(): Promise<void> {
        return this.readyPromise;
    }

    async connect(url: string): Promise<void> {
        return new Promise((resolve, reject) => {
            try {
                this.webSocket = new WebSocket(url);

                this.webSocket.onopen = () => {
                    console.log('WebSocket connected');

                    if (this.webSocket) {
                        // Create message reader/writer for WebSocket
                        const socket = this.webSocket as any;

                        // Set up global message handler for all incoming messages
                        socket.addEventListener('message', (event: MessageEvent) => {
                            try {
                                const message = JSON.parse(event.data);

                                // Log ALL messages for debugging
                                if (message.method) {
                                    console.log(`[LSP Notification] ${message.method}:`, message.params);
                                } else if (message.result || message.error) {
                                    console.log(`[LSP Response] id=${message.id}:`, message.result || message.error);
                                } else {
                                    console.log('[LSP Unknown message]:', message);
                                }

                                // Handle diagram/accept notifications (KLighD actions)
                                if (message.method === 'diagram/accept' && !message.id) {
                                    console.log('✅ DIAGRAM/ACCEPT received! Forwarding to KLighD handler...');
                                    // Forward to KLighD's message handler
                                    if (this.messageHandler && message.params) {
                                        console.log('Calling messageHandler with:', message.params);
                                        this.messageHandler(message.params);
                                    } else {
                                        console.error('⚠️  messageHandler not set or params missing!', {
                                            hasHandler: !!this.messageHandler,
                                            params: message.params
                                        });
                                    }
                                }
                            } catch (e) {
                                console.error('Error parsing message:', e);
                            }
                        });

                        // Simple direct connection without vscode-ws-jsonrpc for now
                        this.connection = {
                            sendRequest: (method: string, params: any) => {
                                return new Promise((resolve, reject) => {
                                    const id = this.requestId++;
                                    const message = {
                                        jsonrpc: '2.0',
                                        id: id,
                                        method: method,
                                        params: params
                                    };
                                    console.log('Sending request:', method, params);
                                    socket.send(JSON.stringify(message));

                                    // Store handler for response
                                    const handler = (event: MessageEvent) => {
                                        try {
                                            const response = JSON.parse(event.data);
                                            if (response.id === id) {
                                                socket.removeEventListener('message', handler);
                                                if (response.error) {
                                                    console.error('Request error:', response.error);
                                                    reject(response.error);
                                                } else {
                                                    console.log('Request response:', response.result);
                                                    resolve(response.result);
                                                }
                                            }
                                        } catch (e) {
                                            console.error('Error parsing response:', e);
                                        }
                                    };
                                    socket.addEventListener('message', handler);
                                });
                            },
                            sendNotification: (method: string, params: any) => {
                                const message = {
                                    jsonrpc: '2.0',
                                    method: method,
                                    params: params
                                };
                                console.log('Sending notification:', method, params);
                                socket.send(JSON.stringify(message));
                            },
                            onNotification: (method: string, handler: (params: any) => void) => {
                                socket.addEventListener('message', (event: MessageEvent) => {
                                    try {
                                        const message = JSON.parse(event.data);
                                        if (message.method === method && !message.id) {
                                            console.log('Handling notification:', method, message.params);
                                            handler(message.params);
                                        }
                                    } catch (e) {
                                        console.error('Error handling notification:', e);
                                    }
                                });
                            }
                        } as any;

                        console.log('LSP connection established');

                        // Initialize LSP and mark as ready
                        this.initialize(this.fileUri).then(() => {
                            this.openDocument(this.fileUri, 'lf').then(() => {
                                console.log('Connection ready');
                                if (this.readyResolve) {
                                    this.readyResolve();
                                }
                            });
                        });

                        resolve();
                    }
                };

                this.webSocket.onerror = (error) => {
                    console.error('WebSocket error:', error);
                    reject(new Error('WebSocket connection failed'));
                };

                this.webSocket.onclose = () => {
                    console.log('WebSocket closed');
                };

            } catch (error) {
                reject(error);
            }
        });
    }

    async initialize(fileUri?: string): Promise<void> {
        if (!this.connection) {
            throw new Error('No connection established');
        }

        // Extract workspace root from file URI (parent directory)
        if (fileUri) {
            const lastSlash = fileUri.lastIndexOf('/');
            if (lastSlash > 0) {
                this.workspaceRoot = fileUri.substring(0, lastSlash);
            }
        }

        // Determine theme based on browser preferences
        const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        const themeKind = prefersDark ? 2 : 1; // 1 = Light, 2 = Dark

        // Send LSP initialize request with proper rootUri and KLighD-specific initialization options
        const initParams = {
            processId: null,
            rootUri: this.workspaceRoot || null,
            clientInfo: { name: 'lf-diagram-viewer' },
            capabilities: {
                textDocument: {
                    synchronization: {
                        dynamicRegistration: true,
                        willSave: false,
                        willSaveWaitUntil: false,
                        didSave: false
                    }
                },
                workspace: {
                    workspaceFolders: true
                }
            },
            initializationOptions: {
                clientDiagramOptions: {},  // Persisted diagram options
                clientColorPreferences: {
                    kind: themeKind
                }
            }
        };

        console.log('Initialize params:', initParams);
        await this.connection.sendRequest('initialize', initParams);
        this.connection.sendNotification('initialized', {});
    }

    async openDocument(uri: string, languageId: string): Promise<void> {
        if (!this.connection) {
            throw new Error('No connection established');
        }

        // Send textDocument/didOpen notification
        this.connection.sendNotification('textDocument/didOpen', {
            textDocument: {
                uri: uri,
                languageId: languageId,
                version: 1,
                text: '' // Server will load from file
            }
        });
    }

    disconnect(): void {
        if (this.webSocket) {
            this.webSocket.close();
            this.webSocket = null;
        }
        this.connection = null;
    }
}
