import asyncio
from fastapi.testclient import TestClient
from app.main import app
from app.core.security import create_access_token
import json

client = TestClient(app)
token = create_access_token("admin", {"id_empresa": "e18bc6d4-d8a4-4cc4-9c02-e0c1fdf40c49", "scopes": "admin"})

resp = client.get("/api/v1/reports/kardex/detalle?fecha_desde=2026-09-01T00:00:00&fecha_hasta=2026-09-22T00:00:00", headers={"Authorization": f"Bearer {token}"})
print(resp.status_code)
if resp.status_code == 200:
    data = resp.json()
    if 'movimientos' in data and data['movimientos']:
        print(json.dumps(data['movimientos'][0], indent=2))
    else:
        print("No hay movimientos")
else:
    print(resp.text)
