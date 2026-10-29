### 1. Diagrama Completo de Detección Dinámica de Dispositivos y Puertos

Este diagrama modela cómo el sistema detecta de forma abierta cualquier báscula, indicador o periférico a través de múltiples canales físicos o de red hacia la aplicación principal.

```mermaid
graph LR
    subgraph BASCULAS ["BÁSCULAS (Dinámicas: 1 a N)"]
        MT["Mettler Toledo / Otras marcas"]
        CS["Cardinal Scale / Otras marcas"]
        BX["[Cualquier Báscula Adicional]"]
    end

    subgraph INDICADORES ["INDICADORES (Dinámicos: 1 a N)"]
        ST["SysTec / Otras marcas"]
        FT["FlinTec / Otras marcas"]
        IX["[Cualquier Indicador Adicional]"]
    end

    subgraph DISPOSITIVOS_PUERTOS ["CAPA DE PUERTOS / DISPOSITIVOS"]
        USB["USB"]
        SERIE["SERIE / COM"]
        TCP["TCP / Red"]
        IMPRESORA["USB-A IMPRESORA"]
    end

    APP["BALANSOFT WS - ESTACIÓN DE PESAJE INDUSTRIAL"]

    %% Conexiones de detección flexibles
    MT --> USB
    CS --> SERIE
    BX --> TCP
    
    ST --> USB
    FT --> SERIE
    IX --> TCP

    USB --> APP
    SERIE --> APP
    TCP --> APP
    IMPRESORA --> APP

```

---

### 2. Diagrama Completo de Conexión por Vínculos Jerárquicos (Ej. 1.1)

Este diagrama refleja la estructura de interconexión donde los dispositivos se agrupan en sub-vínculos jerárquicos (ej. **Vínculo 1.1**, **Vínculo 1.2**), permitiendo una gestión modular y escalable para el motor de la estación de pesaje.

```mermaid
graph LR
    subgraph DISPOSITIVOS ["DISPOSITIVOS DE HARDWARE (Extensibles)"]
        D1["Dispositivo A (Ej: Mettler Toledo)"]
        D2["Dispositivo B (Ej: FlinTec)"]
        D3["Dispositivo C (Ej: Cardinal Scale)"]
        D4["Dispositivo D (Ej: SysTec)"]
        DX["[N Dispositivos Dinámicos]"]
    end

    subgraph ESTRUCTURA_VINCULOS ["VÍNCULOS JERÁRQUICOS"]
        subgraph GRUPO_V1 ["VÍNCULO 1"]
            V1_1["Vínculo 1.1<br>(Sub-canal USB / Serie)"]
        end
        subgraph GRUPO_V2 ["VÍNCULO 2"]
            V1_2["Vínculo 1.2<br>(Sub-canal Serie / TCP)"]
        end
    end

    subgraph GESTOR_VINCULOS ["ADMINISTRADOR CENTRAL"]
        VINCULOS_GEN["VÍNCULOS (Agregador Global)"]
    end

    APP["BALANSOFT WS - ESTACIÓN DE PESAJE INDUSTRIAL"]

    %% Conexiones lógicas y jerárquicas
    D1 --> V1_1
    D2 --> V1_1
    D3 --> V1_2
    D4 --> V1_2
    DX --> V1_1

    V1_1 --> VINCULOS_GEN
    V1_2 --> VINCULOS_GEN

    VINCULOS_GEN --> APP

```