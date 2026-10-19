```mermaid
graph TD
    A([Vehículo se aproxima a la báscula]) --> B{¿Báscula en Cero y Despejada?}
    
    B -- No --> C[Semáforo: ROJO<br>Vehículo espera fuera]
    C --> B
    
    B -- Sí --> D[Semáforo: VERDE<br>Autorización para subir]
    
    D --> E[Vehículo sube a la plataforma y se detiene]
    E --> F[Semáforo cambia a: ROJO<br>Prohibido moverse]
    
    F --> G{¿Lectura de peso Estable?<br>Símbolo 'STABLE' activo}
    
    G -- No: Hay movimiento --> H[Esperando estabilidad...<br>Luz Amarilla opcional]
    H --> G
    
    G -- Sí --> I[Captura de Peso / Registro en Sistema]
    I --> J[Procesamiento: Guardado de datos]
    
    J --> K{¿Pesaje completado?}
    
    K -- Error --> L[Mantiene ROJO<br>Alarma / Notificación]
    
    K -- Exitoso --> M[Semáforo cambia a: VERDE<br>Vía libre para salir]
    
    M --> N[Vehículo abandona la plataforma]
    N --> O[La báscula detecta retorno a Cero]
    O --> P([Fin del ciclo / Báscula en espera])

    style A fill:#3498db,stroke:#2980b9,color:#fff
    style D fill:#2ecc71,stroke:#27ae60,color:#fff
    style M fill:#2ecc71,stroke:#27ae60,color:#fff
    style C fill:#e74c3c,stroke:#c0392b,color:#fff
    style F fill:#e74c3c,stroke:#c0392b,color:#fff
    style L fill:#e74c3c,stroke:#c0392b,color:#fff
    style H fill:#f1c40f,stroke:#f39c12,color:#000
    style B fill:#9b59b6,stroke:#8e44ad,color:#fff
    style G fill:#9b59b6,stroke:#8e44ad,color:#fff
    style K fill:#9b59b6,stroke:#8e44ad,color:#fff```
```