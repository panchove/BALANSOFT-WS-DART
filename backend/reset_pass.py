import asyncio
from sqlalchemy import select
from app.core.database import AsyncSessionLocal  # <-- Nombre correcto
from app.core.security import hash_password
from app.models import Usuario

async def main():
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(Usuario).where(Usuario.email == 'Yohandersanchez2807@gmail.com'))
        usuario = result.scalar_one_or_none()
        if usuario:
            usuario.password_hash = hash_password('Password123')
            await session.commit()
            print("✅ Contraseña actualizada correctamente a: Password123")
        else:
            print("❌ Usuario no encontrado")

if __name__ == "__main__":
    asyncio.run(main())
