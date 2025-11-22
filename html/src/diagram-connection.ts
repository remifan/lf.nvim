/**
 * Simple WebSocket Connection for Sprotty Actions
 *
 * V2 Architecture: Browser communicates with Node sidecar via WebSocket.
 * The sidecar handles all LSP communication through Neovim.
 */

import { ActionMessage } from 'sprotty-protocol';
import { Connection, NotificationType } from '@kieler/klighd-core';

export class DiagramConnection implements Connection {
    private webSocket: WebSocket | null = null;
    private messageHandler: ((message: ActionMessage) => void) | null = null;
    private readyPromise: Promise<void>;
    private readyResolve: (() => void) | null = null;

    constructor() {
        this.readyPromise = new Promise((resolve) => {
            this.readyResolve = resolve;
        });
    }

    // KLighD Connection interface methods
    sendMessage(message: ActionMessage): void {
        // Log all actions, especially element interactions
        const action = message.action as any;
        if (action && (action.kind === 'elementSelected' || action.kind === 'doubleClick' ||
                       action.kind === 'invokeAction' || action.kind?.includes('element'))) {
            console.log('[Connection] Element interaction action:', message);

            // When an element is selected, also send openInSource action
            if (action.kind === 'elementSelected' && action.selectedElementsIDs && action.selectedElementsIDs.length > 0) {
                const elementId = action.selectedElementsIDs[0];
                console.log('[Connection] Sending openInSource for element:', elementId);

                // Send the openInSource action separately
                const openSourceMessage = {
                    clientId: 'lf-diagram-viewer',
                    action: {
                        kind: 'openInSource',
                        elementId: elementId
                    }
                };

                if (this.webSocket && this.webSocket.readyState === WebSocket.OPEN) {
                    this.webSocket.send(JSON.stringify(openSourceMessage));
                }
            }
        } else {
            console.log('[Connection] Sending action to sidecar:', message);
        }

        if (this.webSocket && this.webSocket.readyState === WebSocket.OPEN) {
            this.webSocket.send(JSON.stringify(message));
        } else {
            console.warn('[Connection] WebSocket not ready, cannot send message');
        }
    }

    sendNotification<T extends Record<string, unknown>>(type: NotificationType, payload: T): void {
        console.log('[Connection] Sending notification:', type, payload);
        // For now, wrap notifications as ActionMessages
        this.sendMessage({
            clientId: 'lf-diagram-viewer',
            action: {
                kind: type.toString(),
                ...payload
            }
        });
    }

    onMessageReceived(handler: (message: ActionMessage) => void): void {
        console.log('[Connection] Message handler registered');

        // Wrap the handler to detect when diagram is loaded
        this.messageHandler = (message: ActionMessage) => {
            handler(message);

            // Check if this is a SetModel or UpdateModel action (diagram loaded/updated)
            if (message.action && (message.action.kind === 'setModel' || message.action.kind === 'updateModel')) {
                // Store model for element lookup
                if ((message.action as any).newRoot) {
                    const model = (message.action as any).newRoot;

                    // Dispatch custom event with model data
                    window.dispatchEvent(new CustomEvent('diagram-model-received', {
                        detail: model
                    }));
                }

                // Dispatch a custom event when diagram is ready (only for initial setModel)
                if (message.action.kind === 'setModel') {
                    setTimeout(() => {
                        window.dispatchEvent(new CustomEvent('diagram-ready'));
                    }, 100);
                }
            }

            // Dispatch custom events for element selection
            if (message.action && message.action.kind === 'elementSelected') {
                const action = message.action as any;
                if (action.selectedElementsIDs) {
                    window.dispatchEvent(new CustomEvent('diagram-element-selected', {
                        detail: action.selectedElementsIDs
                    }));
                }
            }
        };
    }

    onReady(): Promise<void> {
        return this.readyPromise;
    }

    async connect(url: string): Promise<void> {
        return new Promise((resolve, reject) => {
            try {
                console.log('[Connection] Connecting to sidecar:', url);
                this.webSocket = new WebSocket(url);

                this.webSocket.onopen = () => {
                    console.log('[Connection] WebSocket connected to sidecar');

                    // Mark as ready immediately (no LSP initialization needed)
                    if (this.readyResolve) {
                        this.readyResolve();
                    }

                    resolve();
                };

                this.webSocket.onmessage = (event: MessageEvent) => {
                    try {
                        const message: ActionMessage = JSON.parse(event.data);
                        console.log('[Connection] Received action from sidecar:', message);

                        // Log action kind for easier tracking
                        if (message.action && message.action.kind) {
                            console.log(`[Connection] Action kind: ${message.action.kind}`);
                        }

                        // Forward to KLighD's message handler
                        if (this.messageHandler) {
                            this.messageHandler(message);
                        }
                    } catch (error) {
                        console.error('[Connection] Error parsing message:', error);
                    }
                };

                this.webSocket.onerror = (error) => {
                    console.error('[Connection] WebSocket error:', error);
                    reject(new Error('WebSocket connection failed'));
                };

                this.webSocket.onclose = () => {
                    console.log('[Connection] WebSocket closed');
                };

            } catch (error) {
                reject(error);
            }
        });
    }

    disconnect(): void {
        if (this.webSocket) {
            this.webSocket.close();
            this.webSocket = null;
        }
    }
}
