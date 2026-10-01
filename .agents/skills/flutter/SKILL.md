---
name: flutter
description: Desarrollo Flutter/Dart para BALANSOFT-WS. Usar para pantallas, servicios, repositorios, almacenamiento local, estado, navegación, integración API y funcionalidades offline.
---

# BALANSOFT-WS Flutter Skill

## Objetivo

Desarrollar el cliente Flutter manteniendo una arquitectura limpia y preparada para funcionamiento offline.

## Capas

Preferir:

presentation
application
domain
data
infrastructure

## Presentation

Widgets y pantallas deben:

- mostrar información;
- recibir interacción;
- disparar acciones;
- observar estado.

Evitar lógica empresarial compleja en widgets.

## Domain

Contiene:

- entidades;
- value objects;
- reglas de negocio puras;
- contratos;
- interfaces.

El dominio no debe depender directamente de Flutter cuando sea evitable.

## Data

Contiene:

- DTOs;
- modelos locales;
- repositories;
- mappers;
- acceso a SQLite;
- acceso a API.

## Infrastructure

Contiene integraciones concretas:

- HTTP;
- SQLite;
- RS232;
- USB;
- TCP;
- impresoras;
- filesystem;
- dispositivos.

## Estado

Usar el mecanismo de gestión de estado ya utilizado por el proyecto.

No introducir otro framework de estado sin necesidad.

## API

Todas las peticiones deben pasar por una capa de servicio/repository.

No realizar HTTP directamente desde widgets.

## Errores

Los errores deben transformarse en estados manejables.

Evitar:

try/catch gigantescos dentro de widgets.

## Offline

Una operación crítica debe poder:

1. ejecutarse localmente;
2. guardarse;
3. agregarse a la cola;
4. sincronizarse posteriormente.

## Identificadores

Las entidades offline deben utilizar identificadores estables.

Preferir UUID cuando corresponda.

## Cambios

Antes de modificar una pantalla:

- buscar su controller/provider/bloc/viewmodel;
- revisar repository;
- revisar modelo;
- revisar API relacionada.

No solucionar problemas de arquitectura solamente desde la UI.