from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)
resp = client.get("/api/v1/health")
print(resp.json())
