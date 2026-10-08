# TÉRMINOS Y CONDICIONES DE USO
## SISTEMA BALANSOFT-WS (Estación de Pesaje Industrial)

**Versión:** 1.0
**Fecha de vigencia:** 08 de octubre de 2026
**Producto:** BALANSOFT-WS
**Proveedor:** BALANSOFT
**Sitio oficial:** https://balansoft.com.ve
**Portal de descargas:** https://balansoft.com.ve/downloads

---

## PREÁMBULO

Los presentes Términos y Condiciones de Uso (en adelante, "los Términos") regulan la adquisición, activación, instalación, uso y operación del sistema **BALANSOFT-WS** (en adelante, "el Sistema" o "el Software"), un sistema de gestión de estación de pesaje industrial para camiones, comercializado exclusivamente bajo **licencias de tipo CENTRAL** con planes **Básico** o **Premium**.

Al adquirir, activar, instalar o utilizar el Sistema, el cliente (en adelante, "el Cliente" o "el Licenciatario") acepta de forma íntegra, expresa e incondicional los presentes Términos. Si el Cliente no está de acuerdo con alguno de ellos, deberá abstenerse de activar y utilizar el Software.

El Cliente declara ser mayor de edad, con capacidad legal para contratar, y contar con las facultades suficientes para obligar a la persona natural o jurídica en cuyo nombre adquiere la licencia.

---

## 1. DEFINICIONES

Para la correcta interpretación de estos Términos, se establecen las siguientes definiciones:

**1.1. Sistema / Software / WS:** El producto BALANSOFT-WS, compuesto por el backend (API FastAPI), el frontend (aplicación Flutter), el componente local **WServer**, los esquemas de base de datos, los instaladores, los binarios, la documentación técnica y cualquier otro componente entregado por el Proveedor.

**1.2. Proveedor / Nosotros:** BALANSOFT, titular de los derechos de comercialización y distribución de todos los productos de la marca BALANSOFT, incluyendo BALANSOFT-WS.

**1.3. Cliente / Licenciatario:** Persona natural o jurídica que adquiere una licencia de uso del Sistema bajo la modalidad CENTRAL.

**1.4. Licencia CENTRAL:** Modalidad de licencia **multisesión** que permite conectar múltiples dispositivos simultáneos a una misma cuenta, hasta el límite de **sesiones/dispositivos** contratado por el Cliente al momento de la compra. Es la **única modalidad de licencia comercializada** para BALANSOFT-WS.

**1.5. Plan Básico:** Plan de alcance funcional reducido, con las restricciones establecidas en la sección 4 de estos Términos.

**1.6. Plan Premium:** Plan de alcance funcional completo, con las funcionalidades avanzadas descritas en la sección 4.

**1.7. Sesión / Dispositivo:** Cada equipo (computadora, estación de trabajo o terminal) autorizado para conectarse simultáneamente a una licencia CENTRAL. El número máximo de sesiones equivale a la cantidad de dispositivos solicitada por el Cliente al momento de la compra.

**1.8. Cuenta Administradora (ADMIN):** Cuenta maestra de la empresa, **creada exclusivamente por el Proveedor**, cuyas credenciales (email y contraseña) son entregadas al Cliente para que realice la activación del producto.

**1.9. Servidor Local:** Dispositivo titular de la licencia sobre el cual se activa la cuenta ADMIN y que ejecuta el componente **WServer** (backend y base de datos local).

**1.10. Trabajador:** Dispositivo cliente delgado que se conecta a la API del Servidor Local, sin base de datos ni WServer propios, y que utiliza credenciales creadas por el administrador de la cuenta.

**1.11. Credenciales:** Conjunto de usuario (email) y contraseña requeridos para autenticarse en el Sistema.

**1.12. Aceptación Digital:** Mecanismo mediante el cual el Cliente manifiesta su consentimiento a estos Términos a través de medios electrónicos, ya sea en la página del producto o en el paquete de instalación, mediante la marcación de una casilla de verificación y/o el uso de un botón de aceptación.

---

## 2. NATURALEZA DEL PRODUCTO Y MODALIDAD DE LICENCIA

**2.1. Única modalidad comercializada:** BALANSOFT-WS se comercializa **exclusivamente bajo licencias de tipo CENTRAL**. No se ofrecen, venden ni activan licencias de tipo MONOPUESTO ni DEMO para este producto.

**2.2. Planes disponibles:** Cada licencia CENTRAL puede adquirirse en uno de dos planes de alcance funcional:
   - **Plan Básico**
   - **Plan Premium**

**2.3. Número de sesiones/dispositivos:** El Cliente **solicita al momento de la compra** la cantidad de dispositivos (sesiones) que desea conectar simultáneamente a su licencia CENTRAL. Dicha cantidad:
   - **Determina el costo total de la licencia** (a mayor cantidad de sesiones, mayor costo).
   - **Es el límite máximo de dispositivos** que pueden conectarse a la vez y recordar la cuenta.
   - Queda registrada en el sistema de licencias del Proveedor y es verificada en cada inicio de sesión.

**2.4. Activación por el Proveedor:** El Cliente **no crea su propia cuenta ADMIN**. El Proveedor:
   - Crea la cuenta ADMIN del Cliente.
   - Le asigna la licencia CENTRAL correspondiente al plan y número de sesiones contratados.
   - Le entrega las **credenciales de la cuenta ADMIN** (email y contraseña).
   - Le indica el procedimiento de activación e instalación.

**2.5. Vínculo de la cuenta al dispositivo:** Al activar el producto con las credenciales entregadas, **la cuenta queda vinculada al dispositivo donde se realizó la activación por primera vez**. Ese dispositivo pasa a ser el **Servidor Local** (titular de la licencia).

**2.6. Vida útil de la licencia:** La licencia CENTRAL tiene la vigencia estipulada en el contrato o comprobante de compra. El Cliente debe renovarla para continuar operando el Sistema una vez vencido el período.

---

## 3. PROCESO DE ADQUISICIÓN, ACTIVACIÓN E INSTALACIÓN

**3.1. Adquisición:** El Cliente adquiere la licencia CENTRAL directamente con el Proveedor o con un distribuidor autorizado, indicando:
   - Plan deseado (Básico o Premium).
   - Número de sesiones/dispositivos a conectar.
   - Datos fiscales y de contacto de la empresa.

**3.2. Creación de la cuenta ADMIN:** Una vez confirmado el pago, el Proveedor:
   - Crea la cuenta ADMIN del Cliente en el sistema de licencias.
   - Asigna la licencia CENTRAL con el tier, plan y número de sesiones contratados.
   - Envía al Cliente las credenciales de acceso de la cuenta ADMIN.

**3.3. Activación del producto (Servidor Local):** El Cliente debe:
   - Descargar el paquete instalador **únicamente desde el portal oficial** https://balansoft.com.ve/downloads.
   - Instalar el Sistema en el dispositivo que será el **Servidor Local**.
   - Introducir las credenciales de la cuenta ADMIN entregadas por el Proveedor.
   - Completar la activación de la licencia, lo que vincula la cuenta a ese dispositivo.

**3.4. Configuración inicial:** Tras la activación, el Cliente (desde la cuenta ADMIN) debe completar la configuración inicial del Sistema, incluyendo datos de empresa, formatos, y la creación de los usuarios operativos.

**3.5. Instalación en dispositivos Trabajador:** Para cada dispositivo adicional autorizado (dentro del límite de sesiones contratadas):
   - El Cliente debe descargar el paquete instalador **únicamente desde el portal oficial** https://balansoft.com.ve/downloads.
   - Instalar el Sistema en **modo Trabajador**.
   - Conectarse a la API del Servidor Local.
   - Utilizar las **credenciales creadas por el administrador de la cuenta** para iniciar sesión.

**3.6. Prohibición de fuentes no oficiales:** Queda terminantemente prohibido descargar, instalar o distribuir el Sistema (o cualquiera de sus componentes) desde fuentes distintas al portal oficial del Proveedor. El Proveedor no garantiza el funcionamiento ni la seguridad de copias obtenidas por medios no autorizados.

---

## 4. PLANES Y RESTRICCIONES

### 4.1. Plan Básico

El Plan Básico incluye la funcionalidad esencial para la gestión de pesaje industrial, con las siguientes **restricciones**:

- **Módulos avanzados excluidos:**
  - Reportes avanzados (transportista, tercero, rango de peso, comparativo mensual).
  - Exportación a formatos múltiples (solo un formato por defecto, según configuración).
  - Sincronización avanzada de catálogos.
  - Diseño de ticket avanzado (solo plantilla estándar).
  - Funcionalidades de auditoría extendida.
  - Ajustes de inventario con conceptos personalizables.
  - Series de numeración múltiples.
- **Límite de funcionalidades:** Las demás que el Proveedor determine y comunique al Cliente al momento de la contratación.

### 4.2. Plan Premium

El Plan Premium incluye **todas las funcionalidades** del Sistema, sin las restricciones del Plan Básico:

- Reportes avanzados (transportista, tercero, rango de peso, comparativo mensual).
- Exportación en múltiples formatos (Excel, PDF, y los que el Proveedor habilite).
- Sincronización avanzada de catálogos.
- Diseño de ticket avanzado (múltiples plantillas, personalización).
- Auditoría extendida.
- Ajustes de inventario con conceptos personalizables.
- Series de numeración múltiples.
- Actualizaciones y funcionalidades nuevas según disponibilidad del Proveedor.

### 4.3. Límite de sesiones/dispositivos

- El número máximo de dispositivos que pueden conectarse **simultáneamente** a la licencia CENTRAL es exactamente la cantidad de sesiones contratada por el Cliente.
- **El Sistema no permite conexiones simultáneas por encima del límite contratado.** Al alcanzar el tope, los dispositivos adicionales recibirán error de "sin cupos disponibles".
- El número de sesiones es fijado al momento de la compra y **solo puede modificarse mediante la adquisición de sesiones adicionales** al Proveedor, lo que ajustará el costo de la licencia.

---

## 5. OBLIGACIONES DEL CLIENTE

El Cliente se obliga a:

**5.1. Uso lícito:** Utilizar el Sistema únicamente para los fines previstos (gestión de pesaje industrial) y conforme a la legislación aplicable.

**5.2. Custodia de credenciales:** Mantener bajo estricta confidencialidad las credenciales de la cuenta ADMIN entregadas por el Proveedor, y ser responsable de todas las acciones realizadas con dichas credenciales.

**5.3. Gestión de usuarios:** Crear, administrar y revocar las credenciales de los usuarios Trabajadores desde la cuenta ADMIN, conforme al límite de sesiones contratadas.

**5.4. No compartir credenciales con terceros no autorizados:** Las credenciales son personales e intransferibles. El Cliente no debe compartirlas con personas ajenas a su organización.

**5.5. Descarga desde fuentes oficiales:** Descargar e instalar el Sistema únicamente desde https://balansoft.com.ve/downloads.

**5.6. Respeto a la propiedad intelectual:** Abstenerse de copiar, reproducir, modificar, descompilar, realizar ingeniería inversa, distribuir, sublicenciar, vender, alquilar o transferir el Software o cualquiera de sus componentes, sin autorización previa y por escrito del Proveedor.

**5.7. No difusión de archivos del sistema:** Abstenerse de compartir, publicar, distribuir o difundir de forma ilegal:
   - Los archivos o binarios del Sistema.
   - Los esquemas de base de datos.
   - Los archivos de la aplicación.
   - Cualquier otro componente técnico del Software.

**5.8. No eludir restricciones:** Abstenerse de eludir, desactivar o sortear los mecanismos de validación de licencia, límite de sesiones, planes o cualquier otra restricción técnica del Sistema.

**5.9. Reportar incidentes:** Informar al Proveedor de cualquier uso no autorizado, filtración de credenciales o incidente de seguridad relacionado con el Sistema.

**5.10. Mantener actualizado el Sistema:** Aplicar las actualizaciones y parches que el Proveedor libere, cuando sean requeridos para el correcto funcionamiento o la seguridad.

---

## 6. PROPIEDAD INTELECTUAL

**6.1. Titularidad:** Todos los derechos de propiedad intelectual sobre el Sistema, incluyendo código fuente, código objeto, binarios, esquemas de base de datos, documentación, diseños, marcas, logotipos y cualquier otro componente, son propiedad exclusiva de BALANSOFT o de sus licenciantes.

**6.2. Licencia de uso:** El Proveedor otorga al Cliente una **licencia de uso limitada, no exclusiva, no transferible y revocable** del Sistema, por el período de vigencia contratado y para el número de sesiones adquirido. Esta licencia no constituye venta ni transferencia de propiedad alguna.

**6.3. Prohibiciones:** Sin autorización previa y por escrito del Proveedor, el Cliente no podrá:
   - Copiar, reproducir o distribuir el Software o sus componentes.
   - Modificar, adaptar, traducir o crear obras derivadas.
   - Descompilar, desensamblar o aplicar ingeniería inversa.
   - Sublicenciar, alquilar, arrendar, prestar o transferir el Software.
   - Eliminar o alterar avisos de propiedad intelectual, marcas o leyendas.
   - Utilizar el Software para desarrollar productos competidores.

**6.4. Consecuencias:** El incumplimiento de esta sección faculta al Proveedor a **revocar la licencia de forma inmediata** y a ejercer las acciones legales que correspondan, incluyendo la reclamación de daños y perjuicios.

---

## 7. CONFIDENCIALIDAD Y PROTECCIÓN DE DATOS

**7.1. Datos del Cliente:** El Proveedor tratará los datos personales y comerciales del Cliente conforme a la legislación aplicable y a su política de privacidad. Los datos operativos (boletos, pesajes, kardex, catálogos) residen en la base de datos local del Cliente y **no son accedidos por el Proveedor**, salvo autorización expresa o requerimiento legal.

**7.2. Datos de la cuenta central:** Para la gestión de licencias, el Proveedor conserva en su base de datos central la información de la cuenta, credenciales globales, licencia y dispositivos registrados. Esta información se utiliza exclusivamente para la validación y administración de la licencia.

**7.3. Confidencialidad del Cliente:** El Cliente se obliga a mantener la confidencialidad de la información técnica del Sistema a la que acceda, y a no divulgarla a terceros no autorizados.

**7.4. Incidentes de seguridad:** En caso de acceso no autorizado o filtración de credenciales, el Cliente deberá notificar de inmediato al Proveedor.

---

## 8. GARANTÍAS Y LIMITACIÓN DE RESPONSABILIDAD

**8.1. Garantía de funcionamiento:** El Proveedor garantiza que el Sistema funcionará sustancialmente conforme a la documentación técnica vigente, siempre que:
   - Se utilice en el hardware y software soportados.
   - Se hayan aplicado las actualizaciones recomendadas.
   - Se respeten los límites de la licencia (plan y sesiones).

**8.2. Exclusiones de garantía:** El Proveedor no garantiza:
   - El funcionamiento ininterrumpido o libre de errores.
   - La compatibilidad con hardware no soportado o modificado.
   - La operación correcta si el Cliente modificó el Software, los esquemas de base de datos o los archivos del Sistema.
   - El funcionamiento de copias obtenidas por fuentes no oficiales.

**8.3. Limitación de responsabilidad:** En la máxima medida permitida por la ley, el Proveedor no será responsable por:
   - Daños indirectos, incidentales, especiales o consecuenciales.
   - Lucro cesante, pérdida de datos o interrupción del negocio.
   - Daños derivados del uso indebido, modificación no autorizada o incumplimiento de estos Términos.
   - La responsabilidad total del Proveedor se limita al monto efectivamente pagado por el Cliente por la licencia en los últimos doce (12) meses.

**8.4. Fuerza mayor:** El Proveedor no será responsable por incumplimientos derivados de causas de fuerza mayor o caso fortuito.

---

## 9. SOPORTE Y MANTENIMIENTO

**9.1. Soporte técnico:** El Proveedor ofrecerá soporte técnico según el plan contratado y los canales establecidos (correo, teléfono, portal). El alcance del soporte se limita al funcionamiento del Software conforme a la documentación.

**9.2. Actualizaciones:** El Proveedor podrá liberar actualizaciones, parches o nuevas versiones. Las actualizaciones de seguridad y correctivos son de aplicación recomendada; las nuevas funcionalidades pueden requerir la contratación del Plan Premium o sesiones adicionales.

**9.3. Exclusiones del soporte:** Quedan fuera del soporte:
   - Problemas derivados de hardware defectuoso o mal configurado.
   - Problemas de red o conectividad del Cliente.
   - Modificaciones no autorizadas del Software.
   - Uso de versiones no oficiales.

---

## 10. VIGENCIA, RENOVACIÓN Y TERMINACIÓN

**10.1. Vigencia:** La licencia tiene la vigencia estipulada en el contrato o comprobante de compra. El uso del Sistema está condicionado al pago oportuno y a la vigencia de la licencia.

**10.2. Renovación:** El Cliente deberá renovar la licencia antes de su vencimiento para continuar operando. El Proveedor notificará oportunamente las condiciones de renovación.

**10.3. Terminación por incumplimiento:** El Proveedor podrá **revocar la licencia de forma inmediata** y sin previo aviso en caso de:
   - Incumplimiento de estos Términos.
   - Uso no autorizado, copia ilegal o difusión de archivos del Sistema.
   - Elusión de los mecanismos de validación o límite de sesiones.
   - Impago de la licencia.
   - Uso del Sistema para fines ilícitos.

**10.4. Efectos de la terminación:** A la terminación, el Cliente deberá cesar todo uso del Sistema y, a requerimiento del Proveedor, eliminar las copias del Software en su poder. Las obligaciones de confidencialidad y propiedad intelectual subsistirán a la terminación.

---

## 11. MODIFICACIONES DE LOS TÉRMINOS

**11.1.** El Proveedor podrá modificar estos Términos cuando lo estime conveniente, notificando al Cliente por los canales oficiales. El uso continuado del Sistema tras la notificación implica la aceptación de los Términos modificados.

**11.2.** Si el Cliente no está de acuerdo con las modificaciones, deberá cesar el uso del Sistema y notificarlo al Proveedor.

---

## 12. LEY APLICABLE Y JURISDICCIÓN

**12.1.** Estos Términos se rigen por las leyes de la República Bolivariana de Venezuela.

**12.2.** Cualquier controversia derivada de la interpretación o ejecución de estos Términos será sometida a la jurisdicción de los tribunales competentes de la ciudad de [ciudad sede del Proveedor], con renuncia a cualquier otro fuero.

---

## 13. DISPOSICIONES GENERALES

**13.1. Integridad:** Estos Términos, junto con el contrato o comprobante de compra, constituyen el acuerdo íntegro entre las partes y sustituyen cualquier acuerdo previo.

**13.2. Nulidad parcial:** Si alguna disposición de estos Términos fuera declarada nula o inejecutable, las demás permanecerán vigentes.

**13.3. No renuncia:** La falta de ejercicio de un derecho por parte del Proveedor no constituye renuncia al mismo.

**13.4. Cesión:** El Cliente no podrá ceder su licencia ni estos Términos sin autorización previa y por escrito del Proveedor.

**13.5. Contacto:** Para consultas sobre estos Términos, el Cliente puede contactar al Proveedor a través de https://balansoft.com.ve o los canales oficiales de soporte.

---

## 14. ACEPTACIÓN DIGITAL

**14.1. Mecanismos de aceptación:** El Cliente podrá aceptar estos Términos mediante:
   - La marcación de una casilla de verificación ("Acepto los Términos y Condiciones") en la **página del producto** o en el **paquete de instalación**.
   - El uso de un botón de aceptación ("Acepto y continúo") en el flujo de instalación o activación.
   - La activación de la licencia con las credenciales entregadas por el Proveedor.

**14.2. Validez de la aceptación digital:** La aceptación digital tiene la misma validez legal que una firma manuscrita, conforme a la legislación aplicable sobre comercio electrónico y firmas electrónicas.

**14.3. Registro de aceptación:** El Proveedor podrá registrar, a efectos probatorios:
   - Fecha y hora de la aceptación.
   - Versión de los Términos aceptada.
   - Identificador del dispositivo o dirección IP desde la que se realizó la aceptación.
   - Credenciales de la cuenta ADMIN utilizadas.

**14.4. Aceptación tácita:** La instalación, activación o uso continuado del Sistema implica la aceptación plena de estos Términos, aun cuando el Cliente no hubiera marcado explícitamente la casilla de verificación.

**14.5. Rechazo:** Si el Cliente no acepta estos Términos, no podrá instalar, activar ni utilizar el Sistema, y deberá abstenerse de descargar el paquete de instalación.

**14.6. Conservación:** El Cliente podrá descargar, imprimir o conservar una copia de estos Términos para su registro personal.

---

## ANEXO A — RESUMEN DE RESTRICCIONES CLAVE

| Aspecto | Regla |
|--------|-------|
| Modalidad de licencia | Únicamente CENTRAL |
| Planes | Básico o Premium |
| Número de sesiones | Solicitado por el Cliente al comprar; define el costo y el límite de dispositivos simultáneos |
| Creación de cuenta ADMIN | Exclusivamente por el Proveedor |
| Entrega de credenciales | El Proveedor envía email y contraseña al Cliente |
| Vínculo de cuenta | Al primer dispositivo donde se activa (Servidor Local) |
| Creación de trabajadores | El Cliente, desde la cuenta ADMIN |
| Descarga del instalador | Solo desde https://balansoft.com.ve/downloads |
| Copia/difusión de archivos | Prohibida |
| Difusión de esquemas de BD | Prohibida |
| Elusión de límites | Prohibida |
| Incumplimiento | Revocación inmediata de la licencia |
| Aceptación | Digital (casilla + botón) en página del producto e instalador |

---

## ANEXO B — AVISO DE ACEPTACIÓN DIGITAL

**Texto sugerido para la casilla de verificación:**

> ☐ He leído, comprendido y acepto los Términos y Condiciones de Uso del Sistema BALANSOFT-WS. Declaro contar con la capacidad legal para obligarme en nombre de la empresa que represento.

**Texto sugerido para el botón de aceptación:**

> [ Acepto y continúo ]

**Texto sugerido para el aviso de registro:**

> Al marcar la casilla y presionar "Acepto y continúo", se registrará su aceptación con fecha, hora, versión de los Términos e identificador del dispositivo. Esta aceptación tiene la misma validez que una firma manuscrita.

**Texto sugerido para el pie del instalador:**

> BALANSOFT-WS · Versión 1.0 · Términos vigentes al 08/10/2026 · https://balansoft.com.ve

---

*Documento vigente. Cualquier modificación será notificada por los canales oficiales del Proveedor.*
