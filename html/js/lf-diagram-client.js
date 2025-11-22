/**
 * Lingua Franca Diagram Client
 * Connects to the LF Language Server and renders interactive diagrams
 */

class LFDiagramClient {
  constructor(options) {
    this.container = document.getElementById(options.container);
    this.fileUri = options.fileUri;
    this.lspServerUrl = options.lspServerUrl;
    this.neovimUrl = options.neovimRpcUrl;

    // WebSocket connection to LSP server
    this.lspWs = null;
    this.lspConnected = false;
    this.messageId = 1;
    this.pendingRequests = new Map();

    // Diagram state
    this.diagramData = null;
    this.svgElement = null;
    this.selectedElement = null;
    this.scale = 1.0;
    this.panX = 0;
    this.panY = 0;

    // UI elements
    this.loadingEl = document.getElementById('loading');
    this.statusIndicator = document.getElementById('status-indicator');
    this.statusText = document.getElementById('status-text');
    this.elementInfo = document.getElementById('element-info');
  }

  /**
   * Initialize the client
   */
  async init() {
    this.updateStatus('loading', 'Connecting to LSP server...');

    if (!this.fileUri) {
      this.showError('No file specified', 'Please provide a file URI in the URL parameters.');
      return;
    }

    // For now, we'll implement a fallback approach since we need to discover
    // the exact KLighD protocol. We'll try multiple approaches:
    // 1. Try to connect to LSP WebSocket
    // 2. Fall back to generating a simple diagram representation
    // 3. Display instructions for using the external viewer

    await this.connectToLSP();
  }

  /**
   * Connect to the LSP server via WebSocket
   */
  async connectToLSP() {
    try {
      // Note: The actual LSP server might not expose WebSocket by default
      // This is a placeholder for when we discover the correct endpoint
      this.lspWs = new WebSocket(this.lspServerUrl);

      this.lspWs.onopen = () => {
        console.log('Connected to LSP server');
        this.lspConnected = true;
        this.updateStatus('connected', 'Connected to LSP server');
        this.requestDiagram();
      };

      this.lspWs.onmessage = (event) => {
        const message = JSON.parse(event.data);
        this.handleLspMessage(message);
      };

      this.lspWs.onerror = (error) => {
        console.error('LSP WebSocket error:', error);
        this.handleConnectionError();
      };

      this.lspWs.onclose = () => {
        console.log('LSP connection closed');
        this.lspConnected = false;
        this.handleConnectionError();
      };

    } catch (error) {
      console.error('Failed to connect to LSP:', error);
      this.handleConnectionError();
    }
  }

  /**
   * Handle connection error by showing fallback options
   */
  handleConnectionError() {
    this.updateStatus('disconnected', 'LSP not available, loading local diagram');

    // Try to load the generated diagram instead
    this.loadGeneratedDiagram();
  }

  /**
   * Request diagram from LSP server
   */
  requestDiagram() {
    if (!this.lspConnected) {
      return;
    }

    const requestId = this.messageId++;

    // This is a guess at the KLighD protocol - needs to be verified
    const request = {
      jsonrpc: '2.0',
      id: requestId,
      method: 'diagram/generate', // or 'keith/diagram' or similar
      params: {
        uri: this.fileUri,
        clientId: 'neovim-lf-diagram',
        diagramType: 'main'
      }
    };

    this.pendingRequests.set(requestId, {
      method: request.method,
      timestamp: Date.now()
    });

    this.lspWs.send(JSON.stringify(request));
    console.log('Requested diagram:', request);
  }

  /**
   * Handle LSP message response
   */
  handleLspMessage(message) {
    console.log('LSP message:', message);

    if (message.id && this.pendingRequests.has(message.id)) {
      const request = this.pendingRequests.get(message.id);
      this.pendingRequests.delete(message.id);

      if (message.result) {
        // Successfully received diagram data
        this.diagramData = message.result;
        this.renderDiagram(message.result);
      } else if (message.error) {
        console.error('LSP error:', message.error);
        this.showError('LSP Error', message.error.message);
      }
    }
  }

  /**
   * Render the diagram using received data
   */
  renderDiagram(data) {
    this.updateStatus('connected', 'Diagram loaded');
    this.loadingEl.style.display = 'none';

    // The actual rendering depends on the format returned by KLighD
    // For now, we'll create a placeholder
    console.log('Rendering diagram with data:', data);

    // TODO: Integrate with Sprotty or use the SVG data directly
    this.generatePlaceholderDiagram();
  }

  /**
   * Load generated diagram from server
   */
  async loadGeneratedDiagram() {
    this.loadingEl.style.display = 'none';
    this.updateStatus('connected', 'Loading generated diagram...');

    try {
      // Fetch the generated SVG
      const response = await fetch('/generated_diagram.svg');
      if (!response.ok) {
        console.log('Generated diagram not found, falling back to placeholder');
        this.generatePlaceholderDiagram();
        return;
      }

      const svgText = await response.text();
      this.container.innerHTML = svgText;
      this.svgElement = this.container.querySelector('svg');

      // Attach click handlers
      this.attachClickHandlers();
      this.updateStatus('connected', 'Diagram loaded');
    } catch (error) {
      console.error('Error loading diagram:', error);
      this.generatePlaceholderDiagram();
    }
  }

  /**
   * Generate a placeholder diagram for demonstration
   * This will be replaced with actual KLighD rendering
   */
  generatePlaceholderDiagram() {
    this.loadingEl.style.display = 'none';
    this.updateStatus('disconnected', 'Showing placeholder diagram');

    // Get filename from URI
    const filename = this.fileUri ? this.fileUri.split('/').pop() : 'Unknown';

    // Create a simple SVG diagram as placeholder
    const svg = `
      <svg width="800" height="600" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <marker id="arrowhead" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
            <polygon points="0 0, 10 3, 0 6" fill="#858585" />
          </marker>
        </defs>

        <!-- Main Reactor -->
        <g class="lf-reactor" data-element="MainReactor" data-line="1" data-col="0">
          <rect x="200" y="100" width="400" height="400" rx="8" class="lf-reactor"/>
          <text x="400" y="130" text-anchor="middle" class="lf-label" font-size="16" font-weight="bold">Main</text>

          <!-- Input Port -->
          <g class="lf-port" data-element="input" data-line="2">
            <circle cx="200" cy="250" r="8" class="lf-port"/>
            <text x="180" y="255" text-anchor="end" class="lf-label">in</text>
          </g>

          <!-- Output Port -->
          <g class="lf-port" data-element="output" data-line="5">
            <circle cx="600" cy="250" r="8" class="lf-port"/>
            <text x="620" y="255" text-anchor="start" class="lf-label">out</text>
          </g>

          <!-- Internal Reactor -->
          <g class="lf-reactor" data-element="SubReactor" data-line="8" data-col="2">
            <rect x="280" y="200" width="240" height="120" rx="6" class="lf-reactor"/>
            <text x="400" y="225" text-anchor="middle" class="lf-label">SubReactor</text>

            <circle cx="280" cy="260" r="6" class="lf-port"/>
            <circle cx="520" cy="260" r="6" class="lf-port"/>
          </g>

          <!-- Connections -->
          <line x1="208" y1="250" x2="274" y2="260" class="lf-connection" marker-end="url(#arrowhead)"/>
          <line x1="526" y1="260" x2="592" y2="250" class="lf-connection" marker-end="url(#arrowhead)"/>
        </g>

        <!-- Info Text -->
        <text x="400" y="550" text-anchor="middle" class="lf-label" fill="#888" font-size="12">
          Placeholder diagram for: ${filename}
        </text>
        <text x="400" y="570" text-anchor="middle" class="lf-label" fill="#666" font-size="11">
          Click elements to navigate to code | Full diagram support coming soon
        </text>
      </svg>
    `;

    this.container.innerHTML = svg;
    this.svgElement = this.container.querySelector('svg');

    // Add click handlers to interactive elements
    this.attachClickHandlers();
  }

  /**
   * Attach click handlers to diagram elements
   */
  attachClickHandlers() {
    const clickableElements = this.container.querySelectorAll('[data-element]');

    clickableElements.forEach(element => {
      element.style.cursor = 'pointer';

      element.addEventListener('click', (e) => {
        e.stopPropagation();
        this.handleElementClick(element);
      });

      element.addEventListener('mouseenter', () => {
        this.highlightElement(element);
      });

      element.addEventListener('mouseleave', () => {
        this.unhighlightElement(element);
      });
    });
  }

  /**
   * Find related visual elements (boxes) near an interactive text element
   */
  findRelatedVisualElements(textElement) {
    // Get the transform attribute to find the position
    const transform = textElement.getAttribute('transform');
    if (!transform) return [];

    // Extract translation values
    const match = transform.match(/matrix\([^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*([^,]+),\s*([^)]+)\)/);
    if (!match) return [];

    const x = parseFloat(match[1]);
    const y = parseFloat(match[2]);

    // Find all <g> elements with transforms near this position
    // KLighD structure: boxes are in sibling groups with similar transforms
    const allGroups = this.svgElement.querySelectorAll('g[transform]');
    const relatedElements = [];

    allGroups.forEach(group => {
      const groupTransform = group.getAttribute('transform');
      const groupMatch = groupTransform.match(/matrix\([^,]+,\s*[^,]+,\s*[^,]+,\s*[^,]+,\s*([^,]+),\s*([^)]+)\)/);

      if (groupMatch) {
        const gx = parseFloat(groupMatch[1]);
        const gy = parseFloat(groupMatch[2]);

        // If the group is close to our text element (within 30px), it's likely related
        const distance = Math.sqrt((gx - x) ** 2 + (gy - y) ** 2);
        if (distance < 30 && group !== textElement) {
          // Find path or rect elements in this group
          const shapes = group.querySelectorAll('path, rect');
          shapes.forEach(shape => relatedElements.push(shape));
        }
      }
    });

    return relatedElements;
  }

  /**
   * Handle click on diagram element
   */
  handleElementClick(element) {
    const elementId = element.getAttribute('data-element');
    const line = parseInt(element.getAttribute('data-line') || '1');
    const col = parseInt(element.getAttribute('data-col') || '0');

    console.log(`Clicked element: ${elementId} at ${line}:${col}`);

    // Select element
    if (this.selectedElement) {
      this.selectedElement.classList.remove('selected');
    }
    this.selectedElement = element;
    element.classList.add('selected');

    // Update info panel
    this.showElementInfo(elementId, line, col);

    // Send jump request to Neovim
    this.jumpToCode(this.fileUri, line, col);
  }

  /**
   * Show element information in info panel
   */
  showElementInfo(elementId, line, col) {
    const html = `
      <dl>
        <dt>Element:</dt>
        <dd><code>${elementId}</code></dd>
        <dt>Location:</dt>
        <dd>Line ${line}, Column ${col}</dd>
        <dt>Type:</dt>
        <dd>Reactor</dd>
      </dl>
      <p style="margin-top: 16px; font-size: 12px; color: #888;">
        Click to navigate to code in Neovim
      </p>
    `;
    this.elementInfo.innerHTML = html;
  }

  /**
   * Highlight diagram element
   */
  highlightElement(element) {
    element.classList.add('highlighted');

    // Find and highlight related visual elements (boxes)
    const relatedElements = this.findRelatedVisualElements(element);
    relatedElements.forEach(shape => {
      // Store original styles
      if (!shape.dataset.originalStroke) {
        shape.dataset.originalStroke = shape.getAttribute('stroke') || '';
        shape.dataset.originalStrokeWidth = shape.getAttribute('stroke-width') || '';
        shape.dataset.originalFill = shape.getAttribute('fill') || '';
      }

      // Apply highlight styles
      shape.setAttribute('stroke', '#4ec9b0');
      shape.setAttribute('stroke-width', '3');
      shape.style.filter = 'drop-shadow(0 0 6px rgba(78, 201, 176, 0.8))';

      // Slightly lighten the fill
      const fill = shape.getAttribute('fill');
      if (fill && fill !== 'none' && fill.startsWith('#')) {
        shape.setAttribute('fill', this.lightenColor(fill));
      }
    });

    // Store for cleanup
    element.dataset.relatedElements = JSON.stringify(
      relatedElements.map(el => Array.from(this.svgElement.querySelectorAll('path, rect')).indexOf(el))
    );
  }

  /**
   * Remove highlight from diagram element
   */
  unhighlightElement(element) {
    element.classList.remove('highlighted');

    // Restore related elements
    if (element.dataset.relatedElements) {
      const indices = JSON.parse(element.dataset.relatedElements);
      const allShapes = this.svgElement.querySelectorAll('path, rect');

      indices.forEach(index => {
        const shape = allShapes[index];
        if (shape && shape.dataset.originalStroke !== undefined) {
          shape.setAttribute('stroke', shape.dataset.originalStroke);
          shape.setAttribute('stroke-width', shape.dataset.originalStrokeWidth);
          shape.setAttribute('fill', shape.dataset.originalFill);
          shape.style.filter = '';
        }
      });

      delete element.dataset.relatedElements;
    }
  }

  /**
   * Lighten a color by mixing with white
   */
  lightenColor(color) {
    // Simple hex color lightening
    const hex = color.replace('#', '');
    const r = parseInt(hex.substr(0, 2), 16);
    const g = parseInt(hex.substr(2, 2), 16);
    const b = parseInt(hex.substr(4, 2), 16);

    // Mix with white (20% lighter)
    const nr = Math.min(255, Math.round(r + (255 - r) * 0.2));
    const ng = Math.min(255, Math.round(g + (255 - g) * 0.2));
    const nb = Math.min(255, Math.round(b + (255 - b) * 0.2));

    return '#' + [nr, ng, nb].map(x => x.toString(16).padStart(2, '0')).join('');
  }

  /**
   * Jump to code location in Neovim
   */
  async jumpToCode(file, line, column) {
    try {
      const response = await fetch(`${this.neovimUrl}/jump`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          file: file,
          line: line,
          column: column
        })
      });

      if (response.ok) {
        console.log(`Jumped to ${file}:${line}:${column}`);
      } else {
        console.error('Failed to jump to code:', response.status);
      }
    } catch (error) {
      console.error('Error sending jump request:', error);
    }
  }

  /**
   * Update status display
   */
  updateStatus(status, message) {
    this.statusIndicator.className = `status-${status}`;
    this.statusText.textContent = message;
  }

  /**
   * Show error message
   */
  showError(title, message) {
    const errorHtml = `
      <div class="error-message">
        <h3>${title}</h3>
        <p>${message}</p>
      </div>
    `;
    this.loadingEl.innerHTML = errorHtml;
  }

  /**
   * Zoom in
   */
  zoomIn() {
    this.scale *= 1.2;
    this.applyTransform();
  }

  /**
   * Zoom out
   */
  zoomOut() {
    this.scale /= 1.2;
    this.applyTransform();
  }

  /**
   * Fit diagram to view
   */
  fitToView() {
    this.scale = 1.0;
    this.panX = 0;
    this.panY = 0;
    this.applyTransform();
  }

  /**
   * Apply transform to SVG
   */
  applyTransform() {
    if (this.svgElement) {
      const g = this.svgElement.querySelector('g');
      if (g) {
        g.setAttribute('transform', `translate(${this.panX}, ${this.panY}) scale(${this.scale})`);
      }
    }
  }

  /**
   * Refresh diagram
   */
  refresh() {
    this.updateStatus('loading', 'Refreshing diagram...');
    if (this.lspConnected) {
      this.requestDiagram();
    } else {
      this.generatePlaceholderDiagram();
    }
  }
}

// Export for use in HTML
window.LFDiagramClient = LFDiagramClient;
