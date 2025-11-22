/**
 * LF Diagram Server - Node Sidecar
 *
 * Acts as the orchestration layer between:
 * - Browser (Sprotty front-end) via WebSocket
 * - Neovim Plugin via TCP/RPC
 *
 * This replaces the VSCode Extension role in the VSCode architecture.
 */

import express from 'express';
import { createServer } from 'http';
import path from 'path';
import { WebSocketServer } from './websocket';
import { NeovimRPCServer } from './neovim-rpc';

const HTTP_PORT = 8765;
const RPC_PORT = 8766;

class DiagramServer {
    private app: express.Application;
    private httpServer: any;
    private wsServer: WebSocketServer;
    private rpcServer: NeovimRPCServer;

    constructor() {
        this.app = express();
        this.httpServer = createServer(this.app);

        // WebSocket server for browser communication
        this.wsServer = new WebSocketServer(this.httpServer);

        // RPC server for Neovim communication
        this.rpcServer = new NeovimRPCServer(RPC_PORT);

        // Wire up message routing between browser and Neovim
        this.setupMessageRouting();

        // Serve static files (Sprotty web app)
        this.setupStaticServer();
    }

    private setupMessageRouting(): void {
        // Browser → Neovim: Forward Sprotty Actions from browser to Neovim
        this.wsServer.onAction((action) => {
            console.log('[Server] Browser → Neovim:', action.action.kind);
            this.rpcServer.sendActionToNeovim(action);
        });

        // Neovim → Browser: Forward diagram updates from Neovim to browser
        this.rpcServer.onAction((action) => {
            console.log('[Server] Neovim → Browser:', action.action.kind);
            this.wsServer.sendActionToBrowser(action);
        });

        // Log connection status
        this.wsServer.onConnect(() => {
            console.log('[Server] Browser connected');
            this.rpcServer.notifyBrowserConnected();
        });

        this.wsServer.onDisconnect(() => {
            console.log('[Server] Browser disconnected');
            this.rpcServer.notifyBrowserDisconnected();
        });
    }

    private setupStaticServer(): void {
        // Serve the Sprotty web app from the html/dist directory
        const staticPath = path.join(__dirname, '../../html/dist');
        console.log('[Server] Serving static files from:', staticPath);
        this.app.use(express.static(staticPath));

        // Serve index.html for all routes (SPA)
        this.app.get('*', (req, res) => {
            res.sendFile(path.join(staticPath, 'index.html'));
        });
    }

    start(): void {
        this.httpServer.listen(HTTP_PORT, () => {
            console.log(`[Server] HTTP server listening on http://localhost:${HTTP_PORT}`);
            console.log(`[Server] WebSocket endpoint: ws://localhost:${HTTP_PORT}`);
        });

        this.rpcServer.start();
        console.log(`[Server] RPC server listening on port ${RPC_PORT}`);
        console.log('[Server] Diagram server ready!');
    }
}

// Start the server
const server = new DiagramServer();
server.start();
