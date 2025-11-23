/**
 * Lingua Franca Diagram Viewer
 * V2 Architecture: Connects to Node sidecar via simple WebSocket
 */

import 'reflect-metadata';

// Import KLighD CSS
import '@kieler/klighd-core/styles/main.css';
import '@kieler/klighd-core/styles/sidebar.css';
import '@kieler/klighd-core/styles/options.css';
import '@kieler/klighd-core/styles/theme.css';

import { createKlighdDiagramContainer, bindServices, requestModel, getActionDispatcher } from '@kieler/klighd-core';
import { Container } from 'inversify';
import { DiagramConnection } from './diagram-connection';

class LFDiagramViewer {
    private container: Container | null = null;
    private connection: DiagramConnection | null = null;
    private currentModel: any = null;

    constructor() {
        this.initialize();
    }

    private async initialize() {
        try {
            this.updateStatus('connecting', 'Connecting to diagram server...');

            // Create KLighD diagram container
            this.container = createKlighdDiagramContainer('diagram-container');

            // Create connection to sidecar
            this.connection = new DiagramConnection();

            // Bind the connection to the container as a KLighD service
            bindServices(this.container, {
                connection: this.connection,
                sessionStorage: window.sessionStorage,
                persistenceStorage: {
                    async getItem<T>(key: string): Promise<T | undefined> {
                        const item = window.localStorage.getItem(key);
                        return item ? JSON.parse(item) as T : undefined;
                    },
                    setItem<T>(key: string, setter: (prev?: T) => T): void {
                        const prevItem = window.localStorage.getItem(key);
                        const prev = prevItem ? JSON.parse(prevItem) as T : undefined;
                        const newValue = setter(prev);
                        window.localStorage.setItem(key, JSON.stringify(newValue));
                    },
                    removeItem(key: string): void {
                        window.localStorage.removeItem(key);
                    },
                    clear(): void {
                        // Don't clear all localStorage, just KLighD-specific items
                        // Leave as no-op for now
                    },
                    onClear(handler: () => void): void {
                        // No-op for now
                    }
                }
            });

            // Connect to sidecar WebSocket (same port as HTTP server)
            const wsUrl = `ws://localhost:8765`;
            await this.connection.connect(wsUrl);

            // Wait for connection to be ready
            await this.connection.onReady();

            this.updateStatus('connected', 'Connected - Requesting diagram...');

            console.log('[Viewer] Connected! Requesting diagram from LSP...');

            // Get dispatcher and request model
            // The browser initiates the diagram request, which goes through the sidecar to Neovim to LSP
            const dispatcher = getActionDispatcher(this.container);

            // Give the SVG container time to render in the DOM
            // This is needed for bounds computation to work
            await new Promise(resolve => setTimeout(resolve, 100));

            // Request diagram with a placeholder clientId - Neovim will provide the actual file URI
            await requestModel(dispatcher, 'lf-diagram-viewer');

            // Wait for diagram to be fully loaded, then center it
            window.addEventListener('diagram-ready', () => {
                console.log('[Viewer] Diagram ready, fitting to screen');
                setTimeout(() => {
                    dispatcher.dispatch({
                        kind: 'fit',
                        elementIds: [],  // Empty array means fit entire diagram
                        padding: 20,
                        maxZoom: 1,
                        animate: true
                    } as any);
                }, 200);
            }, { once: true });

            // Listen for refresh requests from Neovim via custom event
            window.addEventListener('refresh-diagram', () => {
                console.log('[Viewer] 🔄 Refresh requested from Neovim, requesting new diagram...');
                // Trigger a new requestModel to get updated diagram
                requestModel(dispatcher, 'lf-diagram-viewer');
            });

            // Listen for model and element selection via custom events from connection
            window.addEventListener('diagram-model-received', ((event: CustomEvent) => {
                this.currentModel = event.detail;
                console.log('[Viewer] Model stored:', this.currentModel);
            }) as EventListener);

            window.addEventListener('diagram-element-selected', ((event: CustomEvent) => {
                const selectedIds = event.detail;
                console.log('[Viewer] Element selected:', selectedIds);

                if (this.currentModel && selectedIds && selectedIds.length > 0) {
                    selectedIds.forEach((id: string) => {
                        const element = this.findElementById(this.currentModel, id);
                        if (element) {
                            console.log(`[Viewer] Selected element ${id} full data:`, element);
                        }
                    });
                }
            }) as EventListener);

            this.updateStatus('connected', 'Diagram requested');

        } catch (error) {
            console.error('[Viewer] Failed to initialize:', error);
            this.showError('Failed to connect to diagram server: ' + error);
        }
    }

    private updateStatus(state: 'connecting' | 'connected' | 'loading' | 'error', message: string) {
        const indicator = document.getElementById('status-indicator');
        const text = document.getElementById('status-text');

        if (indicator) {
            indicator.className = state === 'connected' ? 'connected' : '';
        }

        if (text) {
            text.textContent = message;
        }
    }

    private findElementById(element: any, id: string): any {
        if (element.id === id) {
            return element;
        }
        if (element.children && Array.isArray(element.children)) {
            for (const child of element.children) {
                const found = this.findElementById(child, id);
                if (found) return found;
            }
        }
        return null;
    }

    private showError(message: string) {
        this.updateStatus('error', 'Error');
        const container = document.getElementById('diagram-container');
        if (container) {
            container.innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; height: 100%; color: #f48771;">
                    <div style="text-align: center; max-width: 600px; padding: 20px;">
                        <h2 style="margin-bottom: 16px;">Error</h2>
                        <p>${message}</p>
                        <p style="margin-top: 20px; font-size: 12px; color: #888;">
                            Check the console for more details.
                        </p>
                    </div>
                </div>
            `;
        }
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    new LFDiagramViewer();
});
