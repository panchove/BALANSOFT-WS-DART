import requests

# URL del WServer local
URL = "http://127.0.0.1:8000/api/v1/auth/login"

# Credenciales
EMAIL = "monandres30@gmail.com"
PASSWORD = "12345678"

print(f"Intentando login en {URL}")
print(f"Email: {EMAIL}")
print(f"Password: {PASSWORD}")
print("-" * 50)

# Hacer la petición
response = requests.post(
    URL,
    json={"email": EMAIL, "password": PASSWORD}
)

print(f"Status Code: {response.status_code}")
print(f"Respuesta: {response.text}")
print("-" * 50)

if response.status_code == 200:
    data = response.json()
    print("✅ LOGIN EXITOSO")
    print(f"Token: {data.get('access_token', '')[:20]}...")
    print(f"Refresh: {data.get('refresh_token', '')[:20]}...")
    print(f"User: {data.get('user', {})}")
    print(f"Empresa: {data.get('empresa', {})}")
else:
    print("❌ LOGIN FALLIDO")
    print(f"Detalle: {response.json().get('detail', 'Sin detalle')}")