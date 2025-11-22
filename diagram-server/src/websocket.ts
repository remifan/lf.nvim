/**
 * WebSocket Server for Browser Communication
 *
 * Handles WebSocket connections from the Sprotty browser client.
 * Receives Sprotty Actions from browser and sends diagram updates to browser.
 */

import { WebSocketServer as WSServer, WebSocket } from 'ws';
import { ActionMessage } from './types';

export class WebSocketServer {
    private wss: WSServer;
    private client: WebSocket | null = null;
    private actionHandler: ((action: ActionMessage) => void) | null = null;
    private connectHandler: (() => void) | null = null;
    private disconnectHandler: (() => void) | null = null;

    constructor(httpServer: any) {
        this.wss = new WSServer({ server: httpServer });
        this.setupWebSocket();
    }

    private setupWebSocket(): void {
        this.wss.on('connection', (ws: WebSocket) => {
            console.log('[WebSocket] Client connected');
            this.client = ws;

            // Notify connection handler
            if (this.connectHandler) {
                this.connectHandler();
            }

            ws.on('message', (data: Buffer) => {
                try {
                    const message = JSON.parse(data.toString());
                    console.log('[WebSocket] Received from browser:', message);

                    // Forward to action handler (which routes to Neovim)
                    if (this.actionHandler && message.action) {
                        this.actionHandler(message as ActionMessage);
                    }
                } catch (error) {
                    console.error('[WebSocket] Error parsing message:', error);
                }
            });

            ws.on('close', () => {
                console.log('[WebSocket] Client disconnected');
                this.client = null;

                // Notify disconnect handler
                if (this.disconnectHandler) {
                    this.disconnectHandler();
                }
            });

            ws.on('error', (error) => {
                console.error('[WebSocket] Error:', error);
            });
        });
    }

    /**
     * Send an Action to the browser
     */
    sendActionToBrowser(action: ActionMessage): void {
        if (this.client && this.client.readyState === WebSocket.OPEN) {
            console.log('[WebSocket] Sending to browser:', action);
            this.client.send(JSON.stringify(action));
        } else {
            console.warn('[WebSocket] No client connected, cannot send action');
        }
    }

    /**
     * Register handler for Actions received from browser
     */
    onAction(handler: (action: ActionMessage) => void): void {
        this.actionHandler = handler;
    }

    /**
     * Register handler for browser connection
     */
    onConnect(handler: () => void): void {
        this.connectHandler = handler;
    }

    /**
     * Register handler for browser disconnection
     */
    onDisconnect(handler: () => void): void {
        this.disconnectHandler = handler;
    }
}
