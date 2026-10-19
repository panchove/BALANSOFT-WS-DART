# GUÍA DEL PROTOCOLO MCP (MODEL CONTEXT PROTOCOL) EN BALANSOFT-WS

El Model Context Protocol (MCP) es un estándar abierto desarrollado por Anthropic para conectar modelos de lenguaje con herramientas y fuentes de datos locales mediante JSON-RPC 2.0.

---

## 1. Modos de Ejecución del Servidor MCP

El script `backend/scripts/mcp_hardware_server.py` implementa el protocolo completo sobre `stdio`:

### Ejecución Directa en Consola
```bash
backend/.venv/bin/python backend/scripts/mcp_hardware_server.py
```

### Mensaje de Inicialización (JSON-RPC)
```json
{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
```

### Respuesta del Servidor
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": { "tools": {} },
    "serverInfo": {
      "name": "balansoft-hardware-mcp",
      "version": "1.0.0"
    }
  }
}
```

### Ejecutar una Herramienta (`tools/call`)
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "parse_scale_frame",
    "arguments": {
      "frame": "ST,GS,+00320.00kg"
    }
  }
}
```

---

## 2. Configuración en Clientes MCP

### En Antigravity / OpenCode
Definido en `.agents/mcp_config.json`:
```json
{
  "mcpServers": {
    "balansoft-hardware": {
      "command": "python3",
      "args": ["backend/scripts/mcp_hardware_server.py"],
      "env": {
        "PYTHONPATH": "backend"
      }
    }
  }
}
```
