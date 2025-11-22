/**
 * RPC Server for Neovim Communication
 *
 * Handles TCP connections from the Neovim plugin.
 * Uses a simple JSON-RPC-like protocol over TCP.
 */

import { createServer, Server, Socket } from 'net';
import { ActionMessage } from './types';

interface RPCMessage {
    method: string;
    params?: any;
}

export class NeovimRPCServer {
    private server: Server;
    private client: Socket | null = null;
    private port: number;
    private actionHandler: ((action: ActionMessage) => void) | null = null;

    constructor(port: number) {
        this.port = port;
        this.server = createServer(this.handleConnection.bind(this));
    }

    private handleConnection(socket: Socket): void {
        console.log('[RPC] Neovim connected');
        this.client = socket;

        let buffer = '';

        socket.on('data', (data: Buffer) => {
            buffer += data.toString();

            // Process complete messages (newline-delimited JSON)
            let newlineIndex;
            while ((newlineIndex = buffer.indexOf('\n')) !== -1) {
                const line = buffer.slice(0, newlineIndex);
                buffer = buffer.slice(newlineIndex + 1);

                try {
                    const message: RPCMessage = JSON.parse(line);
                    this.handleMessage(message);
                } catch (error) {
                    console.error('[RPC] Error parsing message:', error);
                }
            }
        });

        socket.on('close', () => {
            console.log('[RPC] Neovim disconnected');
            this.client = null;
        });

        socket.on('error', (error) => {
            console.error('[RPC] Error:', error);
        });
    }

    private handleMessage(message: RPCMessage): void {
        console.log('[RPC] Received from Neovim:', message);

        switch (message.method) {
            case 'diagram/action':
                // Neovim is sending a diagram action to forward to browser
                if (this.actionHandler && message.params) {
                    this.actionHandler(message.params as ActionMessage);
                }
                break;

            default:
                console.warn('[RPC] Unknown method:', message.method);
        }
    }

    /**
     * Send an Action to Neovim
     */
    sendActionToNeovim(action: ActionMessage): void {
        this.send({
            method: 'diagram/action',
            params: action
        });
    }

    /**
     * Notify Neovim that browser has connected
     */
    notifyBrowserConnected(): void {
        this.send({
            method: 'browser/connected'
        });
    }

    /**
     * Notify Neovim that browser has disconnected
     */
    notifyBrowserDisconnected(): void {
        this.send({
            method: 'browser/disconnected'
        });
    }

    /**
     * Send a message to Neovim
     */
    private send(message: RPCMessage): void {
        if (this.client) {
            const data = JSON.stringify(message) + '\n';
            console.log('[RPC] Sending to Neovim:', message);
            this.client.write(data);
        } else {
            console.warn('[RPC] No client connected, cannot send message');
        }
    }

    /**
     * Register handler for Actions received from Neovim
     */
    onAction(handler: (action: ActionMessage) => void): void {
        this.actionHandler = handler;
    }

    /**
     * Start the RPC server
     */
    start(): void {
        this.server.listen(this.port, () => {
            console.log(`[RPC] Server listening on port ${this.port}`);
        });
    }
}
