> ⚠️ **DOCUMENTO NO AUTORITATIVO** — Especificaciones históricas .NET/WinForms (legacy). Ver `docs/PRD.md` y `docs/ARCH.md`.

# DOCUMENTO MAESTRO DE ESPECIFICACIÓN TÉCNICA COMPLETA
## SISTEMA DE PESAJE AUTOMÁTICO: BALANSOFT

**Versión:** 4.0 (Documentación Completa y Unificada)
**Fecha:** 2026-09-07
**Estado:** Listo para Implementación

---

## ÍNDICE DE CONTENIDOS

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Arquitectura General del Sistema](#2-arquitectura-general-del-sistema)
3. [Modelo de Base de Datos](#3-modelo-de-base-de-datos)
4. [Flujos de Trabajo Detallados](#4-flujos-de-trabajo-detallados)
5. [Módulos de la Interfaz de Usuario](#5-módulos-de-la-interfaz-de-usuario)
6. [Especificación de Endpoints (FastAPI)](#6-especificación-de-endpoints-fastapi)
7. [Estructura del Proyecto (Flutter)](#7-estructura-del-proyecto-flutter)
8. [Reglas de Negocio y Validaciones](#8-reglas-de-negocio-y-validaciones)
9. [Guía de Implementación por Fases](#9-guía-de-implementación-por-fases)
10. [Instructivo para Big Pickel](#10-instructivo-para-big-pickel)

---

## 1. RESUMEN EJECUTIVO

### 1.1 Descripción del Proyecto

**Balansoft** es un sistema de pesaje automático diseñado para básculas de camiones en plantas industriales, centros de distribución y puertos. La aplicación permite gestionar el ciclo completo de pesaje de vehículos de carga, desde la entrada hasta la salida, con un enfoque en la eficiencia operativa y la auditoría de datos.

### 1.2 Alcance del Sistema

| Componente | Descripción |
|------------|-------------|
| **Frontend** | Aplicación Flutter para Web y Mobile |
| **Backend** | API RESTful con FastAPI (Python) |
| **Base de Datos** | PostgreSQL (producción) / SQLite (desarrollo) |
| **Autenticación** | JWT con roles de usuario (OPERADOR, SUPERVISOR, ADMIN) |
| **Hardware** | Integración con básculas digitales (lectura automática de peso) |

### 1.3 Principios de Diseño

1. **Simplicidad:** Eliminación de complejidades innecesarias (ej. catálogos de marcas y modelos de camiones).
2. **Eficiencia:** Creación inline de registros para minimizar interrupciones en el flujo de trabajo.
3. **Flexibilidad:** Soporte para pesaje automático y manual (controlado por roles).
4. **Auditabilidad:** Historial completo de operaciones, anulaciones y reportes.
5. **Seguridad:** Control de acceso basado en roles y validaciones en backend.

---

## 2. ARQUITECTURA GENERAL DEL SISTEMA

### 2.1 Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    FRONTEND (FLUTTER)                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │Dashboard │  │ Pesaje   │  │Historial │  │Catálogos │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS / WebSocket
┌──────────────────────────▼──────────────────────────────────┐
│                    BACKEND (FASTAPI)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │   Auth   │  │ Pesaje   │  │Reportes  │  │Catálogos │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │ SQLAlchemy
┌──────────────────────────▼──────────────────────────────────┐
│                  BASE DE DATOS (POSTGRESQL)                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │Vehiculos │  │ Boletos  │  │Productos │  │Usuarios  │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Tecnologías Utilizadas

| Capa | Tecnología | Versión |
|------|------------|---------|
| **Frontend** | Flutter | 3.16+ |
| | Provider / Riverpod (State Management) | - |
| | Dio (HTTP Client) | - |
| | SharedPreferences (Local Storage) | - |
| **Backend** | FastAPI | 0.100+ |
| | SQLAlchemy (ORM) | 2.0+ |
| | Pydantic (Validación) | 2.0+ |
| | PyJWT (Autenticación) | - |
| | ReportLab (PDF) | - |
| **Base de Datos** | PostgreSQL | 15+ |
| | SQLite (Desarrollo) | 3.0+ |
| **Infraestructura** | Uvicorn (Servidor ASGI) | - |
| | Docker (Opcional) | - |

---

## 3. MODELO DE BASE DE DATOS

### 3.1 Diagrama Entidad-Relación (Simplificado)

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  VEHICULOS  │      │  REMOLQUES  │      │ TRANSPORTES │
├─────────────┤      ├─────────────┤      ├─────────────┤
│ id (PK)     │      │ id (PK)     │      │ id (PK)     │
│ placa       │      │ placa       │      │ codigo      │
│ tara_hab    │      │ tara_hab    │      │ razon_social│
└──────┬──────┘      └──────┬──────┘      └──────┬──────┘
       │                    │                    │
       │                    │                    │
┌──────▼────────────────────▼────────────────────▼──────┐
│              BOLETOS_PESAJE                            │
├───────────────────────────────────────────────────────┤
│ id (PK)                                              │
│ numero_boleto (UNIQUE)                               │
│ vehiculo_id (FK)                                     │
│ remolque_id (FK)                                     │
│ transporte_id (FK)                                   │
│ conductor_id (FK)                                    │
│ producto_id (FK)                                     │
│ almacen_id (FK)                                      │
│ balanza_id (FK)                                      │
│ tercero_id (FK)                                      │
│ peso_entrada                                         │
│ fecha_hora_entrada                                   │
│ peso_salida                                          │
│ fecha_hora_salida                                    │
│ peso_neto (Calculado)                                │
│ estatus (PENDIENTE/COMPLETADO/ANULADO)              │
│ observaciones                                        │
└──────┬───────────────────────────────────────────────┘
       │
┌──────┴────────────────────────────────────────────────┐
│                                                       │
┌──────▼──────┐  ┌─────────────┐  ┌─────────────┐   ┌─────────────┐
│ CONDUCTORES │  │  PRODUCTOS  │  │  ALMACENES  │   │  TERCEROS   │
├─────────────┤  ├─────────────┤  ├─────────────┤   ├─────────────┤
│ id (PK)     │  │ id (PK)     │  │ id (PK)     │   │ id (PK)     │
│ cedula      │  │ codigo      │  │ codigo      │   │ codigo      │
│ nombre      │  │ nombre      │  │ nombre      │   │ razon_social│
│             │  │ densidad    │  │             │   │ tipo        │
└─────────────┘  └─────────────┘  └─────────────┘   └─────────────┘
```

### 3.2 Definición de Tablas (SQLAlchemy)

```python
# app/models.py

from sqlalchemy import Column, Integer, String, Float, DateTime, Text, ForeignKey, Enum, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime
import enum

Base = declarative_base()

# ==================== ENUMS ====================
class TipoTercero(str, enum.Enum):
    CLIENTE = "CLIENTE"
    PROVEEDOR = "PROVEEDOR"
    AMBOS = "AMBOS"

class EstatusBoleto(str, enum.Enum):
    PENDIENTE = "PENDIENTE"
    COMPLETADO = "COMPLETADO"
    ANULADO = "ANULADO"

class RolUsuario(str, enum.Enum):
    OPERADOR = "OPERADOR"
    SUPERVISOR = "SUPERVISOR"
    ADMIN = "ADMIN"

# ==================== TABLAS MAESTRAS ====================

class Vehiculo(Base):
    __tablename__ = "vehiculos"
    
    id = Column(Integer, primary_key=True, index=True)
    placa = Column(String(20), unique=True, index=True, nullable=False)
    tara_habitual = Column(Float, default=0.0)
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="vehiculo")

class Remolque(Base):
    __tablename__ = "remolques"
    
    id = Column(Integer, primary_key=True, index=True)
    placa = Column(String(20), unique=True, index=True, nullable=False)
    tara_habitual = Column(Float, default=0.0)
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="remolque")

class Transporte(Base):
    __tablename__ = "transportes"
    
    id = Column(Integer, primary_key=True, index=True)
    codigo = Column(String(20), unique=True, index=True)
    razon_social = Column(String(100), nullable=False)
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="transporte")

class Conductor(Base):
    __tablename__ = "conductores"
    
    id = Column(Integer, primary_key=True, index=True)
    cedula = Column(String(20), unique=True, index=True, nullable=False)
    nombre = Column(String(100), nullable=False)
    licencia = Column(String(20), nullable=True)
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="conductor")

class Producto(Base):
    __tablename__ = "productos"
    
    id = Column(Integer, primary_key=True, index=True)
    codigo = Column(String(20), unique=True, index=True)
    nombre = Column(String(100), nullable=False)
    descripcion = Column(String(200), nullable=True)
    densidad = Column(Float, default=1.0)
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="producto")

class Almacen(Base):
    __tablename__ = "almacenes"
    
    id = Column(Integer, primary_key=True, index=True)
    codigo = Column(String(20), unique=True, index=True)
    nombre = Column(String(100), nullable=False)
    ubicacion = Column(String(100), nullable=True)
    capacidad_max = Column(Float, default=0.0)
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="almacen")

class Balanza(Base):
    __tablename__ = "balanzas"
    
    id = Column(Integer, primary_key=True, index=True)
    codigo = Column(String(20), unique=True, index=True)
    nombre = Column(String(100), nullable=False)
    puerto_com = Column(String(50), nullable=True)  # COM1, /dev/ttyUSB0, etc.
    ip_address = Column(String(50), nullable=True)   # 192.168.1.100
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="balanza")

class Tercero(Base):
    __tablename__ = "terceros"
    
    id = Column(Integer, primary_key=True, index=True)
    codigo = Column(String(20), unique=True, index=True)
    razon_social = Column(String(100), nullable=False)
    identificacion_fiscal = Column(String(50), nullable=True)
    tipo = Column(Enum(TipoTercero), default=TipoTercero.PROVEEDOR)
    direccion = Column(String(200), nullable=True)
    telefono = Column(String(20), nullable=True)
    activo = Column(Boolean, default=True)
    
    # Relaciones
    boletos = relationship("BoletoPesaje", back_populates="tercero")

class Usuario(Base):
    __tablename__ = "usuarios"
    
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    nombre = Column(String(100), nullable=False)
    email = Column(String(100), nullable=True)
    rol = Column(Enum(RolUsuario), default=RolUsuario.OPERADOR)
    activo = Column(Boolean, default=True)
    fecha_creacion = Column(DateTime, default=datetime.utcnow)

# ==================== TABLA TRANSACCIONAL ====================

class BoletoPesaje(Base):
    __tablename__ = "boletos_pesaje"
    
    id = Column(Integer, primary_key=True, index=True)
    numero_boleto = Column(String(30), unique=True, index=True, nullable=False)
    
    # Llaves Foráneas
    vehiculo_id = Column(Integer, ForeignKey("vehiculos.id"), nullable=False)
    remolque_id = Column(Integer, ForeignKey("remolques.id"), nullable=True)
    transporte_id = Column(Integer, ForeignKey("transportes.id"), nullable=False)
    conductor_id = Column(Integer, ForeignKey("conductores.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    almacen_id = Column(Integer, ForeignKey("almacenes.id"), nullable=False)
    balanza_id = Column(Integer, ForeignKey("balanzas.id"), nullable=False)
    tercero_id = Column(Integer, ForeignKey("terceros.id"), nullable=False)
    
    # Pesos y Tiempos
    peso_entrada = Column(Float, nullable=False)
    fecha_hora_entrada = Column(DateTime, default=datetime.utcnow)
    peso_salida = Column(Float, nullable=True)
    fecha_hora_salida = Column(DateTime, nullable=True)
    peso_neto = Column(Float, nullable=True)  # Calculado: entrada - salida
    
    # Estado
    estatus = Column(Enum(EstatusBoleto), default=EstatusBoleto.PENDIENTE)
    
    # Datos Complementarios
    documento_ref = Column(String(50), nullable=True)
    flete = Column(String(50), nullable=True)
    costo_flete = Column(Float, default=0.0)
    densidad = Column(Float, default=1.0)
    litros = Column(Float, default=0.0)  # Calculado: peso_neto / densidad
    observaciones = Column(Text, nullable=True)
    anulado_por = Column(String(100), nullable=True)
    motivo_anulacion = Column(String(200), nullable=True)
    
    # Relaciones
    vehiculo = relationship("Vehiculo", back_populates="boletos")
    remolque = relationship("Remolque", back_populates="boletos")
    transporte = relationship("Transporte", back_populates="boletos")
    conductor = relationship("Conductor", back_populates="boletos")
    producto = relationship("Producto", back_populates="boletos")
    almacen = relationship("Almacen", back_populates="boletos")
    balanza = relationship("Balanza", back_populates="boletos")
    tercero = relationship("Tercero", back_populates="boletos")
```

---

## 4. FLUJOS DE TRABAJO DETALLADOS

### 4.1 Flujo Estándar: Entrada de Vehículo de Carga

**Propósito:** Registrar la entrada de un vehículo y asignarle un boleto con estado `PENDIENTE`.

#### Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────────────┐
│                   INICIO: NUEVO PESAJE                         │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
              ┌──────────────────────┐
              │ Ingresar Placa del   │
              │ Vehículo             │
              └──────────┬───────────┘
                         ▼
            ┌────────────────────────────┐
            │    ¿Existe en BD?          │
            └────────┬───────────┬────────┘
                     │ SÍ        │ NO
                     ▼           ▼
            ┌──────────────┐  ┌──────────────────────┐
            │ Cargar datos │  │ Registrar Vehículo   │
            │ del Vehículo │  │ (Creación Inline)    │
            └──────────────┘  └──────────┬───────────┘
                     │                   │
                     └────────┬──────────┘
                              ▼
              ┌────────────────────────────────┐
              │ Validar: ¿Tiene boleto        │
              │ PENDIENTE activo?             │
              └────────┬───────────────────────┘
                       ▼
            ┌────────────────────────────────────┐
            │  SÍ: Mostrar error: "Vehículo en  │
            │  Planta. Debe registrar salida."  │
            └────────────────────────────────────┘
                       │
                       ▼ (NO tiene pendiente)
              ┌────────────────────────────────┐
              │ Ingresar/Crear Inline:         │
              │ - Transporte                   │
              │ - Conductor                    │
              │ - Producto                     │
              │ - Almacén                      │
              │ - Cliente/Proveedor            │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Capturar Peso (Automático o    │
              │ Manual según permisos)         │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Asignar Fecha/Hora Entrada     │
              │ (Automático)                   │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Datos Complementarios:         │
              │ - Observaciones                │
              │ - Flete                        │
              │ - Densidad/Litros              │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Guardar Boleto con estado      │
              │ PENDIENTE                      │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ FIN: Boleto Creado             │
              │ Vehículo marcado "En Planta"   │
              └────────────────────────────────┘
```

#### Detalle de Pasos

| Paso | Acción | Detalle Técnico |
|------|--------|-----------------|
| **1** | Ingresar Placa | Campo Autocomplete con búsqueda en tiempo real |
| **2** | Validar Existencia | Si no existe, crear Vehiculo con datos básicos |
| **3** | Validar Pendiente | Consultar boletos con estatus PENDIENTE para esa placa |
| **4** | Registro Inline | Para cada campo, validar existencia y crear si no existe |
| **5** | Capturar Peso | Modo Automático: lectura desde balanza; Modo Manual: input habilitado solo para Admins/Supervisores |
| **6** | Guardar | Generar número de boleto secuencial (ej. CA-00000001) |

### 4.2 Flujo Excepcional: Pesaje Manual

**Propósito:** Permitir el registro de pesaje cuando no hay comunicación con la báscula.

**Restricción:** Solo usuarios con rol `ADMIN` o `SUPERVISOR`.

#### Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────────────┐
│         INICIO: MODO MANUAL (Solo Admins/Supervisores)         │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
              ┌────────────────────────────────┐
              │ Activar Switch "Modo Manual"   │
              │ en la UI                       │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Seleccionar Vehículo con       │
              │ boleto PENDIENTE               │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ ¿Existe boleto PENDIENTE?      │
              └────────┬───────────┬───────────┘
                       │ SÍ        │ NO
                       ▼           ▼
              ┌─────────────────────┐  ┌──────────────────────┐
              │ Cargar datos del    │  │ Mostrar error:       │
              │ boleto de entrada   │  │ "No hay boleto       │
              └────────┬────────────┘  │ pendiente para este  │
                       ▼               │ vehículo"            │
              ┌─────────────────────┐  └──────────────────────┘
              │ Registrar Salida:   │
              │ - Todos los datos   │
              │   son modificables  │
              │ - Peso Entrada NO   │
              │   modificable       │
              └────────┬────────────┘
                       ▼
              ┌────────────────────────────────┐
              │ Ingresar Peso de Salida        │
              │ (Manual)                       │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Calcular: Peso Neto =          │
              │ Peso Entrada - Peso Salida     │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Actualizar Boleto:             │
              │ - Estatus: COMPLETADO          │
              │ - Fecha/Hora Salida            │
              │ - Peso Neto                    │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ FIN: Boleto Completado         │
              │ Vehículo liberado              │
              └────────────────────────────────┘
```

#### Validaciones Críticas

1. **Permisos:** Verificar rol del usuario en backend
2. **Inmutabilidad:** El peso de entrada no puede ser modificado
3. **Consistencia:** El peso de salida debe ser menor que el de entrada (o mayor, dependiendo del tipo de operación)

### 4.3 Flujo: Salida de Vehículo de Carga

**Propósito:** Registrar la salida de un vehículo que tiene un boleto `PENDIENTE`.

#### Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────────────┐
│                   INICIO: REGISTRAR SALIDA                     │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
              ┌────────────────────────────────┐
              │ Buscar vehículo por placa      │
              │ o seleccionar de lista         │
              │ "En Planta"                    │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ ¿Tiene boleto PENDIENTE?       │
              └────────┬───────────┬───────────┘
                       │ SÍ        │ NO
                       ▼           ▼
              ┌─────────────────────┐  ┌──────────────────────┐
              │ Cargar boleto       │  │ Mostrar error:       │
              │ Mostrar datos:      │  │ "Vehículo no tiene   │
              │ - Peso Entrada      │  │ boleto pendiente"    │
              │ - Fecha/Hora Entrada│  └──────────────────────┘
              └────────┬────────────┘
                       ▼
              ┌────────────────────────────────┐
              │ Capturar Peso de Salida        │
              │ (Automático o Manual)          │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Calcular: Peso Neto =          │
              │ Peso Entrada - Peso Salida     │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Actualizar Boleto:             │
              │ - Estatus: COMPLETADO          │
              │ - Fecha/Hora Salida            │
              │ - Peso Neto                    │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ FIN: Boleto Completado         │
              │ Vehículo liberado              │
              └────────────────────────────────┘
```

### 4.4 Flujo: Anulación de Boleto

**Propósito:** Sacar de circulación un boleto, liberando el vehículo asociado.

**Características:**
- Se puede anular en cualquier estado (`PENDIENTE` o `COMPLETADO`)
- Si está `PENDIENTE`, libera el vehículo
- El número de boleto **no se reutiliza**
- Motivo de anulación es **obligatorio**
- **No se contabilizan** en reportes de ingresos/despachos
- **Sí se muestran** en reportes de auditoría

#### Diagrama de Flujo

```
┌─────────────────────────────────────────────────────────────────┐
│               INICIO: ANULAR BOLETO                            │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
              ┌────────────────────────────────┐
              │ Buscar Boleto (ID o Número)    │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ ¿Existe el Boleto?             │
              └────────┬───────────┬───────────┘
                       │ SÍ        │ NO
                       ▼           ▼
              ┌─────────────────────┐  ┌──────────────────────┐
              │ Cargar datos del    │  │ Mostrar error:       │
              │ boleto en formulario│  │ "Boleto no           │
              └────────┬────────────┘  │ encontrado"          │
                       ▼               └──────────────────────┘
              ┌────────────────────────────────┐
              │ Mostrar diálogo de confirmación│
              │ "¿Desea Anular este boleto?"   │
              └────────┬───────────┬───────────┘
                       │ SÍ        │ NO
                       ▼           ▼
              ┌─────────────────────┐  ┌──────────────────────┐
              │ Solicitar Motivo    │  │ Cancelar operación   │
              │ (Campo obligatorio) │  └──────────────────────┘
              └────────┬────────────┘
                       ▼
              ┌────────────────────────────────┐
              │ Marcar boleto como ANULADO     │
              │ - Guardar motivo en            │
              │   observaciones                │
              │ - Registrar usuario que anula  │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ Si estaba PENDIENTE:           │
              │ Liberar vehículo               │
              └────────────┬───────────────────┘
                           ▼
              ┌────────────────────────────────┐
              │ FIN: Boleto ANULADO            │
              │ - No se cuenta en reportes     │
              │ - Sí se muestra en auditoría   │
              │ - Se puede reimprimir con      │
              │   marca de agua "ANULADO"      │
              └────────────────────────────────┘
```

---

## 5. MÓDULOS DE LA INTERFAZ DE USUARIO

### 5.1 Estructura del Menú (Sidebar/Drawer)

```
📊 Dashboard
   ├── KPIs (Pesajes Hoy, En Planta, Toneladas)
   └── Lista de Vehículos en Planta

⚖️ Operaciones de Pesaje
   ├── Nuevo Pesaje (Formulario Entrada/Salida)
   └── Historial de Boletos

🚛 Gestión de Flota
   ├── Vehículos
   └── Remolques

📦 Catálogos
   ├── Productos
   ├── Almacenes
   ├── Conductores
   ├── Transportes
   └── Terceros (Clientes/Proveedores)

⚙️ Configuración
   ├── Balanzas
   ├── Usuarios
   └── Preferencias Generales
```

### 5.2 Módulo: Dashboard

**Propósito:** Vista general del estado de la planta.

**Componentes UI:**

1. **Tarjetas KPIs:**
   ```
   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
   │   Pesajes Hoy    │  │  En Planta       │  │  Toneladas       │
   │      24          │  │      3           │  │   156.5          │
   └──────────────────┘  └──────────────────┘  └──────────────────┘
   ```

2. **Tabla de Vehículos en Planta:**
   ```
   ┌──────────────┬──────────────┬──────────────┬─────────────┐
   │ N° Boleto    │ Placa        │ Hora Entrada │ Acción      │
   ├──────────────┼──────────────┼──────────────┼─────────────┤
   │ CA-00000001  │ ALT369       │ 08:30 AM     │ [Salida]    │
   │ CA-00000002  │ TRV887       │ 09:15 AM     │ [Salida]    │
   │ CA-00000003  │ PLX124       │ 10:00 AM     │ [Salida]    │
   └──────────────┴──────────────┴──────────────┴─────────────┘
   ```

### 5.3 Módulo: Estación de Pesaje (Formulario Unificado)

**Propósito:** Pantalla principal del operador para registrar pesajes.

**Estructura del Formulario:**

#### Sección 1: Cabecera
```
┌─────────────────────────────────────────────────────────────┐
│ N° Boleto: CA-00000004    Estado: 🔵 PENDIENTE            │
│ Fecha: 2026-09-07 08:30:00                                 │
└─────────────────────────────────────────────────────────────┘
```

#### Sección 2: Datos del Vehículo (Autocompletables)
```
┌─────────────────────────────────────────────────────────────┐
│ Placa Vehículo:  [ALT369    ▼]  [➕ Crear]               │
│ Remolque:        [🔘 Sí / 🔘 No]                         │
│ Placa Remolque:  [REMO123  ▼]  [➕ Crear]               │
│ Transporte:      [TRANSPORTE PRUEBA  ▼] [➕ Crear]        │
│ Conductor:       [FULANO DE TAL   ▼] [➕ Crear]           │
│ Producto:        [PRODUCTO 01     ▼] [➕ Crear]           │
│ Almacén:         [ALMACEN 01      ▼] [➕ Crear]           │
│ Balanza:         [Balanza Principal ▼]                    │
│ Cliente/Prov:    [CLIENTE ABC     ▼] [➕ Crear]           │
└─────────────────────────────────────────────────────────────┘
```

#### Sección 3: Lectura de Peso (Panel Central)
```
┌─────────────────────────────────────────────────────────────┐
│                    ⚖️ PESO ACTUAL                          │
│                    ┌───────────────────┐                   │
│                    │   15,234.5  kg    │                   │
│                    └───────────────────┘                   │
│                    [🔘 Auto] [🔘 Manual]                   │
├─────────────────────────────────────────────────────────────┤
│ Entrada:  08:30:00  │  12,450.0 kg    │                    │
│ Salida:   --:--:--  │  --,---.- kg    │                    │
│ ─────────────────────────────────────── │                    │
│ 🟢 Neto Total:      │  2,784.5 kg     │                    │
└─────────────────────────────────────────────────────────────┘
```

#### Sección 4: Datos Complementarios
```
┌─────────────────────────────────────────────────────────────┐
│ Documento Ref:  [FAC-2026-001]                             │
│ Flete:          [TRANSPORTE ABC]                           │
│ Costo Flete:    [1,500.00 Bs]                              │
│ Densidad:       [1.25 kg/L]      Litros: [2,227.6 L]      │
│ Observaciones:  ┌─────────────────────────────────┐        │
│                 │ Carga completa, sin novedades   │        │
│                 └─────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

#### Sección 5: Botonera de Acción
```
┌─────────────────────────────────────────────────────────────┐
│ [🔄 Guardar Entrada]  [📤 Registrar Salida]  [🗑️ Anular] │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 Módulo: Historial de Boletos / Tickets

**Propósito:** Auditoría, impresión y consulta de transacciones pasadas.

**Componentes UI:**

1. **Filtros:**
```
┌─────────────────────────────────────────────────────────────────┐
│ 📅 Fecha: [2026-09-01] ─ [2026-09-07]                         │
│ 📊 Estado: [Todos ▼]  📦 Producto: [Todos ▼]                  │
│ 🚛 Cliente: [Todos ▼]  🔍 Buscar: [__________]               │
│ [🔍 Filtrar] [🔄 Limpiar]                                     │
└─────────────────────────────────────────────────────────────────┘```

2. **Tabla de Resultados:**
```
┌─────────────────────────────────────────────────────────────────┐
│ N° Boleto │ Placa  │ Producto │ Entrada  │ Salida  │ Neto   │ Estado │ Acciones │
├───────────┼────────┼──────────┼──────────┼─────────┼────────┼────────┼──────────┤
│ CA-0000001│ ALT369 │ Producto1│ 12,450.0 │ 9,665.5 │2,784.5 │✅COMP  │ [📄][🗑️] │
│ CA-0000002│ TRV887 │ Producto2│ 8,200.0  │ -       │ -      │⏳PEND  │ [📄][🗑️] │
│ CA-0000003│ PLX124 │ Producto3│ 15,000.0 │ 14,100  │ 900.0  │❌ANUL  │ [📄]     │
└─────────────────────────────────────────────────────────────────┘
```

3. **Acciones por Fila:**
   - `[📄]` Ver Detalle / Reimprimir Ticket
   - `[🗑️]` Anular Boleto (con diálogo de confirmación)

### 5.5 Módulo: Gestión de Catálogos (CRUDs)

**Características Comunes:**
- Listado con búsqueda por campo principal
- Botón "➕ Nuevo" que abre formulario modal
- Acciones: Editar ✏️, Eliminar 🗑️ (o Desactivar)

**Ejemplo: Gestión de Vehículos**
```
┌─────────────────────────────────────────────────────────────────┐
│                         GESTIÓN DE VEHÍCULOS                   │
│ [🔍 Buscar por Placa...]  [➕ Nuevo Vehículo]                  │
├─────────────────────────────────────────────────────────────────┤
│ Placa     │ Tara Habitual │ Estado  │ Acciones                │
├───────────┼───────────────┼─────────┼─────────────────────────┤
│ ALT369    │ 5,200.0 kg    │ Activo  │ [✏️] [🗑️]               │
│ TRV887    │ 4,800.0 kg    │ Activo  │ [✏️] [🗑️]               │
│ PLX124    │ 6,100.0 kg    │ Inactivo│ [✏️] [🔄]               │
└─────────────────────────────────────────────────────────────────┘
```

**Formulario Modal (Nuevo/Editar):**
```
┌─────────────────────────────────────────────────────────────────┐
│                    ✏️ NUEVO VEHÍCULO                           │
├─────────────────────────────────────────────────────────────────┤
│ Placa:          [ALT369]                                       │
│ Tara Habitual:  [5,200.0] kg                                   │
│ Estado:         [🔘 Activo / 🔘 Inactivo]                     │
├─────────────────────────────────────────────────────────────────┤
│ [💾 Guardar]  [❌ Cancelar]                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. ESPECIFICACIÓN DE ENDPOINTS (FASTAPI)

### 6.1 Estructura de Rutas

```
/api/v1/
├── auth/
│   ├── POST /login
│   ├── POST /register
│   ├── POST /refresh-token
│   └── GET /me
├── pesajes/
│   ├── POST /entrada
│   ├── PUT /{boleto_id}/salida
│   ├── PUT /{boleto_id}/anular
│   ├── GET /
│   ├── GET /{boleto_id}
│   ├── GET /{boleto_id}/pdf
│   └── GET /pendientes
├── vehiculos/
│   ├── GET /
│   ├── POST /
│   ├── GET /{vehiculo_id}
│   ├── PUT /{vehiculo_id}
│   └── DELETE /{vehiculo_id}
├── conductores/
│   ├── GET /
│   ├── POST /
│   └── ... (CRUD)
├── transportes/
│   ├── GET /
│   └── ... (CRUD)
├── productos/
│   ├── GET /
│   └── ... (CRUD)
├── almacenes/
│   ├── GET /
│   └── ... (CRUD)
├── terceros/
│   ├── GET /
│   └── ... (CRUD)
├── balanzas/
│   ├── GET /
│   └── ... (CRUD)
└── reportes/
    ├── GET /diario
    ├── GET /por-producto
    └── GET /auditoria
```

### 6.2 Definición de Schemas (Pydantic)

```python
# app/schemas/pesaje.py
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
from enum import Enum

class EstatusBoleto(str, Enum):
    PENDIENTE = "PENDIENTE"
    COMPLETADO = "COMPLETADO"
    ANULADO = "ANULADO"

# ==================== SCHEMAS DE ENTRADA ====================

class PesajeEntradaSchema(BaseModel):
    # Datos del Vehículo
    placa: str
    tara_habitual: Optional[float] = 0.0
    remolque: Optional[str] = None
    remolque_tara: Optional[float] = 0.0
    
    # Datos Maestros (se crearán inline si no existen)
    transporte: str
    conductor: str
    producto: str
    almacen: str
    tercero: str
    
    # Pesaje
    peso_entrada: float
    es_peso_manual: bool = False
    
    # Datos Complementarios
    documento_ref: Optional[str] = None
    flete: Optional[str] = None
    costo_flete: Optional[float] = 0.0
    densidad: Optional[float] = 1.0
    observaciones: Optional[str] = None

class PesajeSalidaSchema(BaseModel):
    peso_salida: float
    es_peso_manual: bool = False

class AnulacionSchema(BaseModel):
    motivo: str  # Campo obligatorio

# ==================== SCHEMAS DE RESPUESTA ====================

class BoletoPesajeResponse(BaseModel):
    id: int
    numero_boleto: str
    vehiculo: dict
    remolque: Optional[dict]
    transporte: dict
    conductor: dict
    producto: dict
    almacen: dict
    balanza: dict
    tercero: dict
    
    peso_entrada: float
    fecha_hora_entrada: datetime
    peso_salida: Optional[float]
    fecha_hora_salida: Optional[datetime]
    peso_neto: Optional[float]
    
    estatus: EstatusBoleto
    
    documento_ref: Optional[str]
    flete: Optional[str]
    costo_flete: float
    densidad: float
    litros: float
    observaciones: Optional[str]
    
    class Config:
        from_attributes = True
```

### 6.3 Implementación de Endpoints Principales

```python
# app/api/v1/endpoints/pesajes.py

from fastapi import APIRouter, HTTPException, Depends, status
from sqlalchemy.orm import Session
from datetime import datetime
from typing import List, Optional

from app.core.deps import get_db, get_current_user
from app.models import (
    BoletoPesaje, Vehiculo, Remolque, Transporte, Conductor,
    Producto, Almacen, Balanza, Tercero, Usuario,
    EstatusBoleto, RolUsuario
)
from app.schemas.pesaje import (
    PesajeEntradaSchema, PesajeSalidaSchema,
    AnulacionSchema, BoletoPesajeResponse
)
from app.services.pesaje import generar_numero_boleto, calcular_litros

router = APIRouter()

# ==================== UTILITY FUNCTIONS ====================

def get_or_create_model(db: Session, model_class, search_fields: dict, create_fields: dict):
    """Función genérica para obtener o crear un registro."""
    instance = db.query(model_class).filter_by(**search_fields).first()
    if not instance:
        instance = model_class(**create_fields)
        db.add(instance)
        db.commit()
        db.refresh(instance)
    return instance

# ==================== ENDPOINTS ====================

@router.post("/entrada", status_code=status.HTTP_201_CREATED, response_model=BoletoPesajeResponse)
def registrar_pesaje_entrada(
    data: PesajeEntradaSchema,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    """
    Registrar entrada de vehículo de carga.
    - Crea registros inline si no existen.
    - Valida que el vehículo no tenga un boleto PENDIENTE activo.
    """
    # 1. Obtener o crear Vehículo
    vehiculo = get_or_create_model(
        db, Vehiculo,
        {"placa": data.placa.upper()},
        {"placa": data.placa.upper(), "tara_habitual": data.tara_habitual}
    )
    
    # 2. Validar que no tenga boleto PENDIENTE
    pendiente = db.query(BoletoPesaje).filter(
        BoletoPesaje.vehiculo_id == vehiculo.id,
        BoletoPesaje.estatus == EstatusBoleto.PENDIENTE
    ).first()
    
    if pendiente:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El vehículo {data.placa} ya tiene un boleto pendiente (N° {pendiente.numero_boleto})."
        )
    
    # 3. Obtener o crear Remolque (si aplica)
    remolque = None
    if data.remolque:
        remolque = get_or_create_model(
            db, Remolque,
            {"placa": data.remolque.upper()},
            {"placa": data.remolque.upper(), "tara_habitual": data.remolque_tara}
        )
    
    # 4. Obtener o crear Transporte
    transporte = get_or_create_model(
        db, Transporte,
        {"razon_social": data.transporte},
        {"razon_social": data.transporte}
    )
    
    # 5. Obtener o crear Conductor
    conductor = get_or_create_model(
        db, Conductor,
        {"cedula": data.conductor},
        {"cedula": data.conductor, "nombre": data.conductor}
    )
    
    # 6. Obtener o crear Producto
    producto = get_or_create_model(
        db, Producto,
        {"nombre": data.producto},
        {"nombre": data.producto, "densidad": data.densidad}
    )
    
    # 7. Obtener o crear Almacen
    almacen = get_or_create_model(
        db, Almacen,
        {"nombre": data.almacen},
        {"nombre": data.almacen}
    )
    
    # 8. Obtener o crear Tercero
    tercero = get_or_create_model(
        db, Tercero,
        {"razon_social": data.tercero},
        {"razon_social": data.tercero}
    )
    
    # 9. Validar pesaje manual
    if data.es_peso_manual and current_user.rol not in [RolUsuario.ADMIN, RolUsuario.SUPERVISOR]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tiene permisos para registrar pesajes en modo manual."
        )
    
    # 10. Obtener balanza por defecto (o permitir selección)
    balanza = db.query(Balanza).filter_by(activo=True).first()
    if not balanza:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No hay balanzas activas configuradas en el sistema."
        )
    
    # 11. Crear boleto
    nuevo_boleto = BoletoPesaje(
        numero_boleto=generar_numero_boleto(db),
        vehiculo_id=vehiculo.id,
        remolque_id=remolque.id if remolque else None,
        transporte_id=transporte.id,
        conductor_id=conductor.id,
        producto_id=producto.id,
        almacen_id=almacen.id,
        balanza_id=balanza.id,
        tercero_id=tercero.id,
        peso_entrada=data.peso_entrada,
        fecha_hora_entrada=datetime.utcnow(),
        estatus=EstatusBoleto.PENDIENTE,
        documento_ref=data.documento_ref,
        flete=data.flete,
        costo_flete=data.costo_flete,
        densidad=data.densidad,
        litros=calcular_litros(data.peso_entrada, data.densidad),
        observaciones=data.observaciones
    )
    
    db.add(nuevo_boleto)
    db.commit()
    db.refresh(nuevo_boleto)
    
    return nuevo_boleto


@router.put("/{boleto_id}/salida", response_model=BoletoPesajeResponse)
def registrar_pesaje_salida(
    boleto_id: int,
    data: PesajeSalidaSchema,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    """
    Registrar salida de vehículo.
    - Solo aplica a boletos en estado PENDIENTE.
    - Calcula automáticamente el peso neto.
    """
    boleto = db.query(BoletoPesaje).filter(BoletoPesaje.id == boleto_id).first()
    
    if not boleto:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Boleto no encontrado."
        )
    
    if boleto.estatus != EstatusBoleto.PENDIENTE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"El boleto está en estado {boleto.estatus.value}. Solo se pueden completar boletos PENDIENTES."
        )
    
    # Validar pesaje manual
    if data.es_peso_manual and current_user.rol not in [RolUsuario.ADMIN, RolUsuario.SUPERVISOR]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No tiene permisos para registrar pesajes en modo manual."
        )
    
    # Validar que el peso de salida sea válido
    if data.peso_salida >= boleto.peso_entrada:
        # Nota: Dependiendo del tipo de operación, esto podría ser válido o no.
        # Aquí asumimos que el peso de salida debe ser menor (descarga).
        pass
    
    # Actualizar boleto
    boleto.peso_salida = data.peso_salida
    boleto.peso_neto = boleto.peso_entrada - boleto.peso_salida
    boleto.fecha_hora_salida = datetime.utcnow()
    boleto.estatus = EstatusBoleto.COMPLETADO
    boleto.litros = calcular_litros(boleto.peso_neto, boleto.densidad)
    
    db.commit()
    db.refresh(boleto)
    
    return boleto


@router.put("/{boleto_id}/anular", response_model=dict)
def anular_boleto_pesaje(
    boleto_id: int,
    data: AnulacionSchema,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    """
    Anular un boleto en cualquier estado.
    - Si está PENDIENTE, libera el vehículo.
    - El número de boleto no se reutiliza.
    - Se requiere motivo de anulación.
    """
    boleto = db.query(BoletoPesaje).filter(BoletoPesaje.id == boleto_id).first()
    
    if not boleto:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Boleto no encontrado."
        )
    
    if boleto.estatus == EstatusBoleto.ANULADO:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Este boleto ya está anulado."
        )
    
    # Registrar motivo de anulación
    motivo = data.motivo
    observacion_anulacion = f"ANULADO por {current_user.nombre}. Motivo: {motivo}"
    
    if boleto.observaciones:
        boleto.observaciones = f"{boleto.observaciones} | {observacion_anulacion}"
    else:
        boleto.observaciones = observacion_anulacion
    
    boleto.estatus = EstatusBoleto.ANULADO
    boleto.anulado_por = current_user.nombre
    boleto.motivo_anulacion = motivo
    
    db.commit()
    db.refresh(boleto)
    
    # NOTA: El vehículo queda liberado automáticamente porque ya no tiene
    # boletos con estatus PENDIENTE.
    
    return {
        "message": "Boleto anulado exitosamente.",
        "boleto_id": boleto.id,
        "numero_boleto": boleto.numero_boleto,
        "estatus": boleto.estatus.value
    }


@router.get("/pendientes", response_model=List[BoletoPesajeResponse])
def obtener_pendientes(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    """Obtener todos los boletos en estado PENDIENTE (Vehículos en Planta)."""
    boletos = db.query(BoletoPesaje).filter(
        BoletoPesaje.estatus == EstatusBoleto.PENDIENTE
    ).order_by(BoletoPesaje.fecha_hora_entrada).all()
    
    return boletos


@router.get("/{boleto_id}", response_model=BoletoPesajeResponse)
def obtener_boleto(
    boleto_id: int,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    """Obtener detalle de un boleto específico."""
    boleto = db.query(BoletoPesaje).filter(BoletoPesaje.id == boleto_id).first()
    
    if not boleto:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Boleto no encontrado."
        )
    
    return boleto


@router.get("/", response_model=List[BoletoPesajeResponse])
def listar_boletos(
    skip: int = 0,
    limit: int = 100,
    estatus: Optional[EstatusBoleto] = None,
    fecha_inicio: Optional[datetime] = None,
    fecha_fin: Optional[datetime] = None,
    placa: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    """Listar boletos con filtros."""
    query = db.query(BoletoPesaje)
    
    if estatus:
        query = query.filter(BoletoPesaje.estatus == estatus)
    
    if fecha_inicio:
        query = query.filter(BoletoPesaje.fecha_hora_entrada >= fecha_inicio)
    
    if fecha_fin:
        query = query.filter(BoletoPesaje.fecha_hora_entrada <= fecha_fin)
    
    if placa:
        query = query.join(Vehiculo).filter(Vehiculo.placa.ilike(f"%{placa}%"))
    
    boletos = query.order_by(BoletoPesaje.fecha_hora_entrada.desc()).offset(skip).limit(limit).all()
    
    return boletos
```

### 6.4 Endpoints de Catálogos (CRUD Genérico)

```python
# app/api/v1/endpoints/vehiculos.py

from fastapi import APIRouter, HTTPException, Depends, status
from sqlalchemy.orm import Session
from typing import List, Optional

from app.core.deps import get_db, get_current_user
from app.models import Vehiculo, Usuario
from app.schemas.vehiculo import VehiculoCreate, VehiculoUpdate, VehiculoResponse

router = APIRouter()

@router.get("/", response_model=List[VehiculoResponse])
def listar_vehiculos(
    search: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    query = db.query(Vehiculo)
    if search:
        query = query.filter(Vehiculo.placa.ilike(f"%{search}%"))
    return query.offset(skip).limit(limit).all()

@router.post("/", response_model=VehiculoResponse, status_code=status.HTTP_201_CREATED)
def crear_vehiculo(
    data: VehiculoCreate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    existing = db.query(Vehiculo).filter(Vehiculo.placa == data.placa.upper()).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ya existe un vehículo con esta placa."
        )
    vehiculo = Vehiculo(**data.dict())
    db.add(vehiculo)
    db.commit()
    db.refresh(vehiculo)
    return vehiculo

# ... (similar para PUT, DELETE, GET por ID)
```

---

## 7. ESTRUCTURA DEL PROYECTO (FLUTTER)

### 7.1 Estructura de Carpetas

```
lib/
├── main.dart                          # Punto de entrada de la aplicación
├── app.dart                           # Configuración principal de la app
├── routes.dart                        # Definición de rutas
│
├── core/                              # Capa de infraestructura compartida
│   ├── constants/
│   │   ├── app_constants.dart        # Colores, tamaños, textos
│   │   ├── api_constants.dart        # URLs de API, endpoints
│   │   └── route_constants.dart      # Nombres de rutas
│   │
│   ├── models/                        # Modelos de datos compartidos
│   │   ├── vehiculo.dart
│   │   ├── boleto_pesaje.dart
│   │   ├── conductor.dart
│   │   ├── producto.dart
│   │   └── usuario.dart
│   │
│   ├── services/                      # Servicios de red y almacenamiento
│   │   ├── api_client.dart           # Cliente HTTP con Dio
│   │   ├── auth_service.dart         # Autenticación JWT
│   │   ├── pesaje_service.dart       # Servicios de pesaje
│   │   ├── catalogo_service.dart     # Servicios de catálogos
│   │   ├── local_storage.dart        # SharedPreferences
│   │   └── websocket_service.dart    # Conexión a balanza (opcional)
│   │
│   ├── widgets/                       # Widgets reutilizables
│   │   ├── layout/
│   │   │   ├── sidebar.dart          # Menú lateral
│   │   │   ├── navbar.dart           # Barra superior
│   │   │   └── main_layout.dart      # Layout principal
│   │   ├── forms/
│   │   │   ├── autocomplete_field.dart  # Campo con búsqueda y creación inline
│   │   │   ├── custom_text_field.dart
│   │   │   ├── custom_dropdown.dart
│   │   │   └── toggle_switch.dart
│   │   ├── tables/
│   │   │   ├── data_table_widget.dart
│   │   │   └── paginated_table.dart
│   │   ├── modals/
│   │   │   ├── confirmation_dialog.dart
│   │   │   └── form_modal.dart
│   │   └── cards/
│   │       ├── kpi_card.dart
│   │       └── info_card.dart
│   │
│   ├── providers/                     # State Management (Provider/Riverpod)
│   │   ├── auth_provider.dart
│   │   ├── pesaje_provider.dart
│   │   ├── catalogo_provider.dart
│   │   └── theme_provider.dart
│   │
│   └── utils/
│       ├── validators.dart           # Validaciones de formularios
│       ├── formatters.dart           # Formateadores de números/fechas
│       ├── date_utils.dart
│       └── helpers.dart
│
├── features/                          # Módulos de funcionalidad
│   │
│   ├── auth/                          # Autenticación
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── login_screen.dart
│   │   │   │   ├── register_screen.dart
│   │   │   │   └── forgot_password_screen.dart
│   │   │   └── widgets/
│   │   │       └── auth_form.dart
│   │   └── data/
│   │       ├── models/
│   │       │   └── user_model.dart
│   │       └── repositories/
│   │           └── auth_repository.dart
│   │
│   ├── dashboard/                     # Panel de control
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   └── dashboard_screen.dart
│   │   │   └── widgets/
│   │   │       ├── kpi_cards_row.dart
│   │   │       └── pending_vehicles_table.dart
│   │   └── data/
│   │       └── repositories/
│   │           └── dashboard_repository.dart
│   │
│   ├── pesaje/                        # Núcleo del sistema
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── nuevo_pesaje_screen.dart      # Formulario principal
│   │   │   │   ├── historial_screen.dart          # Listado con filtros
│   │   │   │   └── detalle_boleto_screen.dart     # Detalle y acciones
│   │   │   └── widgets/
│   │   │       ├── peso_display.dart              # Visualizador de peso
│   │   │       ├── pesaje_form.dart               # Formulario completo
│   │   │       ├── autocomplete_creatable.dart    # Autocomplete con creación inline
│   │   │       ├── filtros_historial.dart
│   │   │       └── boleto_card.dart               # Card de boleto
│   │   └── data/
│   │       ├── models/
│   │       │   ├── boleto_pesaje.dart
│   │       │   └── pesaje_request.dart
│   │       └── repositories/
│   │           └── pesaje_repository.dart
│   │
│   ├── catalogo/                      # Gestión de catálogos
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── catalogo_general_screen.dart  # Menú de catálogos
│   │   │   │   ├── vehiculos_screen.dart
│   │   │   │   ├── conductores_screen.dart
│   │   │   │   ├── transportes_screen.dart
│   │   │   │   ├── productos_screen.dart
│   │   │   │   ├── almacenes_screen.dart
│   │   │   │   └── terceros_screen.dart
│   │   │   └── widgets/
│   │   │       ├── catalogo_form.dart             # Formulario modal genérico
│   │   │       └── catalogo_table.dart            # Tabla genérica
│   │   └── data/
│   │       ├── models/
│   │       │   ├── vehiculo.dart
│   │       │   ├── conductor.dart
│   │       │   ├── producto.dart
│   │       │   └── ...
│   │       └── repositories/
│   │           ├── vehiculo_repository.dart
│   │           ├── conductor_repository.dart
│   │           └── ...
│   │
│   └── configuracion/                 # Configuración del sistema
│       ├── presentation/
│       │   ├── screens/
│       │   │   ├── balanzas_screen.dart
│       │   │   ├── usuarios_screen.dart
│       │   │   └── preferencias_screen.dart
│       │   └── widgets/
│       │       └── balanza_form.dart
│       └── data/
│           ├── models/
│           │   ├── balanza.dart
│           │   └── usuario.dart
│           └── repositories/
│               └── config_repository.dart
│
├── assets/                            # Recursos estáticos
│   ├── images/
│   │   ├── logo.png
│   │   └── icons/
│   ├── fonts/
│   └── translations/                  # Internacionalización
│
└── test/                              # Pruebas unitarias
    ├── core/
    ├── features/
    │   ├── auth/
    │   ├── pesaje/
    │   └── catalogo/
    └── integration/
```

### 7.2 Diagrama de Navegación

```
┌─────────────────────────────────────────────────────────────────┐
│                         SPLASH SCREEN                          │
└────────────────────────┬────────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                         LOGIN SCREEN                           │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Usuario: [________________]                              │  │
│  │ Contraseña: [________________]                          │  │
│  │ [🔑 Iniciar Sesión]  [📝 Registrarse]                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────────────┘
                         ▼ (Autenticación exitosa)
┌─────────────────────────────────────────────────────────────────┐
│                    MAIN LAYOUT (Sidebar + Navbar)              │
│  ┌──────────────┬──────────────────────────────────────────┐   │
│  │  SIDEBAR     │              CONTENT AREA               │   │
│  │              │                                         │   │
│  │ 📊 Dashboard │     (Pantalla activa según ruta)        │   │
│  │ ⚖️ Pesaje    │                                         │   │
│  │ 📋 Historial │                                         │   │
│  │ 🚛 Flota     │                                         │   │
│  │ 📦 Catálogos │                                         │   │
│  │ ⚙️ Config    │                                         │   │
│  └──────────────┴──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. REGLAS DE NEGOCIO Y VALIDACIONES

### 8.1 Reglas de Negocio Críticas

| # | Regla | Descripción | Implementación |
|---|-------|-------------|----------------|
| 1 | **Creación Inline** | Todos los campos del formulario de pesaje deben permitir la creación automática de registros si no existen en la base de datos. | Backend: Función `get_or_create_model()` en cada endpoint. Frontend: Autocomplete con opción "+ Crear". |
| 2 | **Un Pendiente por Vehículo** | Un vehículo NO puede tener dos boletos con estado PENDIENTE al mismo tiempo. | Backend: Consulta de boletos PENDIENTE antes de crear uno nuevo. Frontend: Validación previa y mensaje de error. |
| 3 | **Pesaje Manual** | Solo usuarios con rol ADMIN o SUPERVISOR pueden registrar pesos manualmente. | Backend: Validación en endpoints. Frontend: Ocultar/deshabilitar campo de peso manual según rol. |
| 4 | **Anulación de Boletos** | Se puede anular un boleto en cualquier estado. Si está PENDIENTE, libera el vehículo. El motivo es obligatorio. | Backend: Endpoint PUT /pesajes/{id}/anular con campo motivo. Frontend: Diálogo de confirmación con campo de texto. |
| 5 | **Inmutabilidad del Número de Boleto** | El número de boleto es generado secuencialmente y nunca se reutiliza, incluso si el boleto es anulado. | Backend: Función `generar_numero_boleto()` basada en el último ID. |
| 6 | **Cálculo de Peso Neto** | `peso_neto = peso_entrada - peso_salida` | Backend: Se calcula al registrar la salida. Frontend: Se muestra en tiempo real. |
| 7 | **Cálculo de Litros** | `litros = peso_neto / densidad` | Backend: Se calcula al registrar la salida. Frontend: Se muestra en tiempo real. |
| 8 | **Auditoría de Anulaciones** | Las anulaciones NO se contabilizan en reportes de ingresos/despachos, pero SÍ se muestran en reportes de auditoría. | Backend: Filtros en endpoints de reportes excluyendo ANULADO. |
| 9 | **Reimpresión de Boletos** | Un boleto anulado se puede reimprimir mostrando una marca de agua "ANULADO". | Backend: Lógica en generación de PDF. Frontend: Botón de reimpresión siempre visible. |
| 10 | **Control de Acceso** | Los roles de usuario determinan qué acciones pueden realizar. | Backend: Dependencia `get_current_user()` con validación de roles. Frontend: Ocultar/mostrar elementos según rol. |

### 8.2 Validaciones de Formulario

#### Formulario de Nuevo Pesaje

| Campo | Validación | Mensaje de Error |
|-------|------------|------------------|
| Placa Vehículo | Obligatorio, máximo 20 caracteres | "La placa del vehículo es obligatoria." |
| Transporte | Obligatorio | "El transporte es obligatorio." |
| Conductor | Obligatorio | "El conductor es obligatorio." |
| Producto | Obligatorio | "El producto es obligatorio." |
| Almacén | Obligatorio | "El almacén es obligatorio." |
| Balanza | Obligatorio, debe existir en catálogo | "Seleccione una balanza activa." |
| Tercero | Obligatorio | "Seleccione un cliente o proveedor." |
| Peso Entrada (Automático) | Mayor a 0 | "El peso debe ser mayor a 0." |
| Peso Entrada (Manual) | Mayor a 0, solo si es supervisor | "No tiene permisos para ingresar peso manual." |
| Observaciones | Opcional, máximo 500 caracteres | "Las observaciones no pueden exceder 500 caracteres." |

#### Formulario de Salida

| Campo | Validación | Mensaje de Error |
|-------|------------|------------------|
| Peso Salida (Automático) | Mayor a 0 | "El peso debe ser mayor a 0." |
| Peso Salida (Manual) | Mayor a 0, solo si es supervisor | "No tiene permisos para ingresar peso manual." |
| Peso Neto | Debe ser mayor o igual a 0 | "El peso neto no puede ser negativo." |

#### Formulario de Anulación

| Campo | Validación | Mensaje de Error |
|-------|------------|------------------|
| Motivo | Obligatorio, mínimo 10 caracteres | "El motivo de anulación es obligatorio (mínimo 10 caracteres)." |

### 8.3 Roles y Permisos

| Acción | OPERADOR | SUPERVISOR | ADMIN |
|--------|----------|------------|-------|
| Ver Dashboard | ✅ | ✅ | ✅ |
| Registrar Entrada (Automático) | ✅ | ✅ | ✅ |
| Registrar Entrada (Manual) | ❌ | ✅ | ✅ |
| Registrar Salida (Automático) | ✅ | ✅ | ✅ |
| Registrar Salida (Manual) | ❌ | ✅ | ✅ |
| Ver Historial | ✅ | ✅ | ✅ |
| Anular Boleto | ❌ | ✅ | ✅ |
| Reimprimir Ticket | ✅ | ✅ | ✅ |
| Gestionar Vehículos | ❌ | ✅ | ✅ |
| Gestionar Conductores | ❌ | ✅ | ✅ |
| Gestionar Productos | ❌ | ✅ | ✅ |
| Gestionar Transportes | ❌ | ✅ | ✅ |
| Gestionar Almacenes | ❌ | ✅ | ✅ |
| Gestionar Terceros | ❌ | ✅ | ✅ |
| Gestionar Balanzas | ❌ | ❌ | ✅ |
| Gestionar Usuarios | ❌ | ❌ | ✅ |
| Configurar Preferencias | ❌ | ❌ | ✅ |
| Ver Reportes de Auditoría | ❌ | ✅ | ✅ |

---

## 9. GUÍA DE IMPLEMENTACIÓN POR FASES

### Fase 1: Configuración Inicial (Día 1-2)

**Objetivo:** Preparar el entorno de desarrollo y configurar la infraestructura básica.

#### Backend
- [ ] Crear proyecto FastAPI
- [ ] Configurar conexión a PostgreSQL/SQLite
- [ ] Definir modelos ORM (SQLAlchemy)
- [ ] Configurar autenticación JWT
- [ ] Crear endpoint de login/register

#### Frontend
- [ ] Crear proyecto Flutter
- [ ] Configurar tema y rutas
- [ ] Implementar estructura de carpetas
- [ ] Crear widgets base (Sidebar, Navbar)
- [ ] Configurar cliente HTTP (Dio)
- [ ] Implementar pantalla de login

### Fase 2: Implementación de Catálogos (Día 3-5)

**Objetivo:** Crear los CRUDs para todas las tablas maestras.

#### Backend
- [ ] Endpoints CRUD para Vehículos
- [ ] Endpoints CRUD para Remolques
- [ ] Endpoints CRUD para Transportes
- [ ] Endpoints CRUD para Conductores
- [ ] Endpoints CRUD para Productos
- [ ] Endpoints CRUD para Almacenes
- [ ] Endpoints CRUD para Terceros
- [ ] Endpoints CRUD para Balanzas
- [ ] Endpoints CRUD para Usuarios

#### Frontend
- [ ] Pantalla de listado de Vehículos
- [ ] Pantalla de listado de Conductores
- [ ] Pantalla de listado de Productos
- [ ] Pantalla de listado de Almacenes
- [ ] Pantalla de listado de Transportes
- [ ] Pantalla de listado de Terceros
- [ ] Formularios modales para cada catálogo

### Fase 3: Núcleo de Pesaje (Día 6-10)

**Objetivo:** Implementar la funcionalidad principal de pesaje.

#### Backend
- [ ] Endpoint POST /pesajes/entrada
- [ ] Endpoint PUT /pesajes/{id}/salida
- [ ] Endpoint GET /pesajes/pendientes
- [ ] Endpoint GET /pesajes/
- [ ] Función get_or_create_model()
- [ ] Función generar_numero_boleto()
- [ ] Validación de duplicidad de PENDIENTE
- [ ] Validación de permisos para pesaje manual

#### Frontend
- [ ] Pantalla Nuevo Pesaje (formulario completo)
- [ ] Widget Autocomplete con creación inline
- [ ] Widget de visualización de peso
- [ ] Lógica de alternancia Entrada/Salida
- [ ] Cálculo en tiempo real de Peso Neto y Litros
- [ ] Integración con autenticación para permisos

### Fase 4: Historial y Anulaciones (Día 11-13)

**Objetivo:** Implementar la gestión de boletos y anulaciones.

#### Backend
- [ ] Endpoint PUT /pesajes/{id}/anular
- [ ] Endpoint GET /pesajes/{id}
- [ ] Generación de PDF con ReportLab
- [ ] Lógica de marca de agua para boletos anulados

#### Frontend
- [ ] Pantalla Historial con filtros
- [ ] Tabla paginada de boletos
- [ ] Detalle de boleto (pantalla o modal)
- [ ] Diálogo de confirmación para anulación
- [ ] Botón de reimpresión de ticket
- [ ] Mostrar boletos ANULADO con indicador visual

### Fase 5: Dashboard y Reportes (Día 14-15)

**Objetivo:** Implementar el panel de control y reportes.

#### Backend
- [ ] Endpoint GET /reportes/diario
- [ ] Endpoint GET /reportes/por-producto
- [ ] Endpoint GET /reportes/auditoria

#### Frontend
- [ ] Pantalla Dashboard con KPIs
- [ ] Tabla de vehículos en planta
- [ ] Gráficos simples (opcional)
- [ ] Exportar reportes a PDF/Excel

### Fase 6: Integración con Balanza y Pruebas (Día 16-18)

**Objetivo:** Integrar la lectura automática de peso y realizar pruebas completas.

#### Backend
- [ ] WebSocket para lectura de balanza
- [ ] Configuración de puertos COM/IP

#### Frontend
- [ ] Conexión WebSocket para peso en tiempo real
- [ ] Modo Automático/Manual con toggle
- [ ] Validación completa de roles y permisos

#### Pruebas
- [ ] Pruebas unitarias de los modelos
- [ ] Pruebas de integración de la API
- [ ] Pruebas de UI (Widget Tests)
- [ ] Pruebas de flujo completo (E2E)

### Fase 7: Despliegue (Día 19-20)

**Objetivo:** Preparar el sistema para producción.

- [ ] Configurar variables de entorno
- [ ] Migraciones de base de datos (Alembic)
- [ ] Build de Flutter para Web
- [ ] Despliegue en servidor (VPS/AWS)
- [ ] Configurar SSL/HTTPS
- [ ] Documentación de usuario final
- [ ] Capacitación a operadores

---

## 10. INSTRUCTIVO PARA BIG PICKEL

### Instrucciones Finales para el Modelo de IA

> **"Eres Big Pickel, un experto arquitecto de software especializado en Flutter (Frontend) y FastAPI (Backend). Tu misión es implementar el sistema 'Balansoft', un software de pesaje automático para básculas de camiones, basado en la documentación completa que se te ha proporcionado.**
>
> **Contexto del Proyecto:**
> - **Nombre del Sistema:** Balansoft
> - **Propósito:** Gestión de pesaje de vehículos de carga (entrada, salida, historial, anulaciones).
> - **Usuarios:** Operadores, Supervisores y Administradores (control de acceso por roles).
> - **Alcance:** Aplicación Web/Mobile con backend API RESTful.
>
> **Requerimientos Funcionales Principales:**
> 1.  **Creación Inline:** Todos los campos del formulario de pesaje (Vehículo, Transporte, Conductor, Producto, Almacén, Tercero) deben permitir la creación automática del registro si no existe en la base de datos.
> 2.  **Pesaje Automático y Manual:** El sistema debe soportar lectura automática desde la báscula. El modo manual solo debe estar disponible para usuarios con rol `SUPERVISOR` o `ADMIN`.
> 3.  **Control de Estado PENDIENTE:** Un vehículo no puede tener dos boletos en estado `PENDIENTE` al mismo tiempo.
> 4.  **Anulación de Boletos:** Los boletos se pueden anular en cualquier estado. Si está `PENDIENTE`, libera al vehículo. El motivo es obligatorio.
> 5.  **Cálculos Automáticos:**
>     - `peso_neto = peso_entrada - peso_salida`
>     - `litros = peso_neto / densidad`
> 6.  **Historial y Tickets:** Listado de boletos con filtros y acciones (ver detalle, reimprimir ticket PDF con marca de agua "ANULADO" si corresponde).
> 7.  **CRUDs Maestros:** Gestión completa de Vehículos, Conductores, Transportes, Productos, Almacenes, Terceros y Balanzas.
> 8.  **Dashboard:** KPIs de actividad diaria y lista de vehículos en planta.
> 9.  **Autenticación y Autorización:** Login con JWT y control de acceso basado en roles (`OPERADOR`, `SUPERVISOR`, `ADMIN`).
>
> **Requerimientos Técnicos:**
> - **Backend (FastAPI):**
>   - Utilizar SQLAlchemy como ORM con PostgreSQL (producción) y SQLite (desarrollo).
>   - Implementar endpoints RESTful con validaciones Pydantic.
>   - Utilizar JWT para autenticación.
>   - Implementar la lógica de creación inline en los endpoints de pesaje.
> - **Frontend (Flutter):**
>   - Utilizar una estructura modular (Clean Architecture / Feature-First).
>   - Implementar `Autocomplete` con opción de creación inline para todos los campos del formulario de pesaje.
>   - State Management: Provider o Riverpod.
>   - Conexión HTTP con Dio.
>   - Diseño responsive (Web y Mobile).
>
> **Estructura de Código:**
> - Seguir la estructura de carpetas definida en el documento (core/, features/, assets/).
> - En backend, organizar por dominios (api/v1/endpoints/, models/, schemas/, services/).
>
> **Reglas de Negocio a Implementar:**
> 1.  Función `get_or_create_model()` para manejar la creación inline.
> 2.  Validación de duplicidad de boletos `PENDIENTE` antes de crear una nueva entrada.
> 3.  Validación de permisos para pesaje manual (rol `SUPERVISOR` o `ADMIN`).
> 4.  Generación secuencial de números de boleto (ej. CA-00000001, CA-00000002, ...).
> 5.  Cálculo automático de `peso_neto` y `litros` al registrar la salida.
> 6.  En la anulación, registrar el motivo y el usuario que anula.
> 7.  En la generación de PDF, mostrar marca de agua "ANULADO" si el boleto está anulado.
>
> **Orden de Prioridad de Implementación:**
> 1.  **Backend:** Modelos de datos y endpoints de autenticación.
> 2.  **Backend + Frontend:** CRUDs de catálogos (para poblar datos de prueba).
> 3.  **Backend + Frontend:** Flujo completo de Entrada (con creación inline).
> 4.  **Backend + Frontend:** Flujo completo de Salida y cálculo de neto.
> 5.  **Backend + Frontend:** Anulación de boletos.
> 6.  **Frontend:** Historial y Dashboard.
> 7.  **Backend + Frontend:** Generación de tickets PDF.
>
> **Recursos Adicionales:**
> - Utilizar `reportlab` para la generación de PDF en FastAPI.
> - Utilizar `bcrypt` o `passlib` para el hashing de contraseñas.
> - En Flutter, utilizar `shared_preferences` para almacenar el token JWT localmente.
> - En Flutter, utilizar `web_socket_channel` para la conexión con la balanza (opcional).
>
> **Entregables Finales:**
> - Código fuente completo (Backend y Frontend) con comentarios en español.
> - Instrucciones de instalación y despliegue en un archivo README.md.
> - Colección de endpoints de Postman para probar la API.
>
> **Nota Importante:** La documentación proporcionada es completa y detallada. Sigue las especificaciones al pie de la letra. Cualquier duda sobre el flujo, consulta los diagramas de flujo incluidos en la documentación."