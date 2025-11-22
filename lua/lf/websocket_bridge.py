#!/usr/bin/env python3
"""
WebSocket Bridge for LF Diagram Server
Bridges WebSocket connections from browser to LSP stdio
"""

import asyncio
import json
import subprocess
import sys
from pathlib import Path

try:
    import websockets
except ImportError:
    print("ERROR: websockets module not found. Install with: pip install websockets", file=sys.stderr)
    sys.exit(1)


class LSPBridge:
    def __init__(self, lsp_jar_path):
        self.lsp_jar_path = lsp_jar_path
        self.lsp_process = None
        self.clients = set()

    async def start_lsp(self):
        """Start the LSP server process"""
        print(f"Starting LSP server: {self.lsp_jar_path}", file=sys.stderr)
        self.lsp_process = await asyncio.create_subprocess_exec(
            "java", "-Xmx2G", "-jar", self.lsp_jar_path,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        print("LSP server started", file=sys.stderr)

        # Start reading LSP output
        asyncio.create_task(self.read_lsp_output())
        asyncio.create_task(self.read_lsp_errors())

    async def read_lsp_output(self):
        """Read LSP stdout and broadcast to all connected clients"""
        while True:
            try:
                # Read Content-Length header
                header = await self.lsp_process.stdout.readline()
                if not header:
                    print("LSP stdout closed", file=sys.stderr)
                    break

                header = header.decode('utf-8').strip()

                # Skip empty lines
                if not header:
                    continue

                if not header.startswith('Content-Length:'):
                    print(f"Unexpected header: {header}", file=sys.stderr)
                    continue

                content_length = int(header.split(':')[1].strip())

                # Read empty line
                await self.lsp_process.stdout.readline()

                # Read content
                content = await self.lsp_process.stdout.read(content_length)
                message = json.loads(content.decode('utf-8'))

                print(f"LSP → Client: {json.dumps(message)[:200]}...", file=sys.stderr)

                # Broadcast to all connected WebSocket clients
                if self.clients:
                    message_str = json.dumps(message)
                    await asyncio.gather(*[
                        client.send(message_str)
                        for client in self.clients
                    ], return_exceptions=True)

            except Exception as e:
                print(f"Error reading LSP output: {e}", file=sys.stderr)
                import traceback
                traceback.print_exc(file=sys.stderr)
                break

    async def read_lsp_errors(self):
        """Read LSP stderr for logging"""
        while True:
            try:
                line = await self.lsp_process.stderr.readline()
                if not line:
                    break
                print(f"LSP: {line.decode('utf-8').strip()}", file=sys.stderr)
            except Exception as e:
                print(f"Error reading LSP errors: {e}", file=sys.stderr)
                break

    async def send_to_lsp(self, message):
        """Send message to LSP stdin"""
        try:
            print(f"Client → LSP: {json.dumps(message)[:200]}...", file=sys.stderr)

            content = json.dumps(message)
            content_bytes = content.encode('utf-8')
            header = f"Content-Length: {len(content_bytes)}\r\n\r\n"

            self.lsp_process.stdin.write(header.encode('utf-8'))
            self.lsp_process.stdin.write(content_bytes)
            await self.lsp_process.stdin.drain()

        except Exception as e:
            print(f"Error sending to LSP: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc(file=sys.stderr)

    async def handle_client(self, websocket):
        """Handle WebSocket client connection"""
        print(f"Client connected: {websocket.remote_address}", file=sys.stderr)
        self.clients.add(websocket)

        try:
            async for message_str in websocket:
                try:
                    message = json.loads(message_str)
                    await self.send_to_lsp(message)
                except json.JSONDecodeError as e:
                    print(f"Invalid JSON from client: {e}", file=sys.stderr)
                except Exception as e:
                    print(f"Error handling client message: {e}", file=sys.stderr)

        except websockets.exceptions.ConnectionClosed:
            print(f"Client disconnected: {websocket.remote_address}", file=sys.stderr)
        finally:
            self.clients.remove(websocket)

    async def run(self, host='127.0.0.1', port=5007):
        """Run the WebSocket bridge server"""
        await self.start_lsp()

        print(f"Starting WebSocket server on ws://{host}:{port}", file=sys.stderr)
        async with websockets.serve(self.handle_client, host, port):
            print(f"WebSocket bridge ready on ws://{host}:{port}", file=sys.stdout, flush=True)
            await asyncio.Future()  # Run forever

    def cleanup(self):
        """Cleanup resources"""
        if self.lsp_process:
            self.lsp_process.terminate()


async def main():
    if len(sys.argv) < 2:
        print("Usage: websocket_bridge.py <lsp-jar-path> [port]", file=sys.stderr)
        sys.exit(1)

    lsp_jar_path = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5007

    if not Path(lsp_jar_path).exists():
        print(f"ERROR: LSP JAR not found: {lsp_jar_path}", file=sys.stderr)
        sys.exit(1)

    bridge = LSPBridge(lsp_jar_path)

    try:
        await bridge.run(port=port)
    except KeyboardInterrupt:
        print("\nShutting down...", file=sys.stderr)
    finally:
        bridge.cleanup()


if __name__ == '__main__':
    asyncio.run(main())
