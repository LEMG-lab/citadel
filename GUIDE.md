# Citadel — Guia completa del usuario

> Version 1.4 | Ultima actualizacion: marzo 2026

---

## Tabla de contenidos

1. [Primeros pasos](#1-primeros-pasos)
2. [Touch ID](#2-touch-id)
3. [Entries tipo Login](#3-entries-tipo-login)
4. [Templates](#4-templates)
5. [Secure Notes](#5-secure-notes)
6. [Custom Fields](#6-custom-fields)
7. [TOTP / 2FA](#7-totp--2fa)
8. [Favorites y Folders](#8-favorites-y-folders)
9. [Fuzzy Search](#9-fuzzy-search)
10. [Password Health / Watchtower](#10-password-health--watchtower)
11. [Breach Check HIBP](#11-breach-check-hibp)
12. [Secure Sharing](#12-secure-sharing)
13. [Multiple Vaults](#13-multiple-vaults)
14. [Backup y Recovery](#14-backup-y-recovery)
15. [Menu Bar](#15-menu-bar)
16. [Keyboard Shortcuts](#16-keyboard-shortcuts)
17. [Seguridad](#17-seguridad)
18. [KeePassXC / iPhone](#18-keepassxc--iphone)
19. [Troubleshooting](#19-troubleshooting)

---

## 1. Primeros pasos

### Que es Citadel

Citadel es un gestor de passwords local para macOS. Tus passwords se guardan en un archivo `.kdbx` (formato KeePass) encriptado en tu Mac — nunca en la nube, nunca en servidores externos. Tu eres dueno de tus datos.

### Crear tu primer vault

1. Abre Citadel desde `/Applications/Citadel.app`
2. La primera vez veras la pantalla de creacion de vault
3. Escribe un **master password** — este es el password que protege todos los demas
4. Opcionalmente, agrega un **key file** (un archivo adicional que se necesita junto con el password)
5. Haz clic en **Create Vault**

El vault se crea en `~/.citadel/personal.kdbx` por defecto.

### Que es el master password

Es la unica contrasena que necesitas memorizar. Todos tus passwords estan protegidos detras de ella. Si la olvidas, **no hay forma de recuperar tus datos** — Citadel no tiene servidores ni mecanismo de recuperacion remoto.

**Tips para un buen master password:**

- Usa al menos 4-5 palabras aleatorias (ejemplo: `caballo bateria grapa correcta`)
- No uses datos personales (cumpleanos, nombres de mascotas)
- No reutilices un password que ya usas en otro sitio
- Consideralo como la llave maestra de tu casa — tratalo con ese nivel de importancia

### Que es KDF y por que importa

KDF significa **Key Derivation Function** — es el algoritmo que convierte tu master password en la llave de encriptacion.

Citadel usa **Argon2id**, considerado el mejor KDF disponible actualmente. Tiene tres parametros:

| Preset | Memoria | Iteraciones | Paralelismo |
|---------|---------|-------------|-------------|
| Standard | 256 MB | 3 | 4 threads |
| High | 512 MB | 5 | 4 threads |
| **Maximum** (default) | **1 GB** | **10** | **4 threads** |

**Por que importa:** Un atacante que robe tu archivo `.kdbx` necesitaria probar miles de millones de passwords. El KDF hace que cada intento sea extremadamente lento y costoso en memoria. Con Maximum, cada intento requiere 1 GB de RAM — hacer un ataque de fuerza bruta es practicamente imposible.

**El trade-off:** Un KDF mas fuerte significa que abrir tu vault tarda un poco mas (1-3 segundos en Maximum). Vale la pena.

Para cambiar el preset: **Settings > KDF Strength** y selecciona el nivel deseado. El vault se re-encripta con los nuevos parametros.

---

## 2. Touch ID

### Que es

Touch ID en Citadel te permite desbloquear tu vault con tu huella digital en lugar de escribir el master password cada vez.

### Como funciona internamente

Citadel NO usa el Keychain de Apple. Usa un sistema basado en archivos:

1. Al activar Touch ID, genera un **nonce** aleatorio
2. Encripta tu master password usando XOR con una llave derivada del nonce + identificador unico del dispositivo
3. Guarda el nonce (`.bio-nonce`) y el blob encriptado (`.bio-blob`) en `~/.citadel/` con permisos `0600` (solo tu usuario puede leerlos)

### Como activar Touch ID

1. Desbloquea tu vault con tu master password (Touch ID solo se puede activar cuando el vault esta abierto)
2. Ve a **Settings** (icono de engranaje o `Cmd+,`)
3. En la seccion **Security**, activa el toggle **Touch ID**
4. Autenticaate con tu huella cuando el sistema lo pida
5. Veras el mensaje "Touch ID enrolled successfully"

### Cada cuanto pide el password completo

Citadel requiere tu master password completo **cada 72 horas** como medida de seguridad. Esto asegura que:

- No olvides tu master password por depender exclusivamente de Touch ID
- Si alguien tiene acceso fisico a tu Mac, la ventana de vulnerabilidad es limitada

Cuando se cumplen las 72 horas, Touch ID dejara de funcionar temporalmente y veras solo el campo de password. Una vez que ingreses tu master password, Touch ID vuelve a funcionar.

### Que pasa si Touch ID falla

- El campo de master password siempre esta disponible como alternativa
- Si falla la lectura biometrica, simplemente escribe tu password manualmente
- Si Touch ID falla repetidamente, desactivalo y vuelvelo a activar en Settings

### Auto-trigger

Cuando abres Citadel y Touch ID esta activado, automaticamente intenta autenticarte con tu huella despues de 0.5 segundos. No necesitas hacer clic — solo pon tu dedo en el sensor.

### Cuando se desactiva automaticamente

- Al cambiar tu master password, Touch ID se desactiva y necesitas re-activarlo
- Despues de 72 horas sin ingresar el password completo

---

## 3. Entries tipo Login

### Que es

Un entry tipo Login es la forma mas comun de guardar credenciales: usuario, password, URL y notas.

### Crear un entry

1. Haz clic en **+** en la barra de herramientas (o `Cmd+N`)
2. Selecciona la template **Login** (es la default)
3. Llena los campos:
   - **Title**: Nombre del servicio (ej. "GitHub")
   - **Username**: Tu usuario o email
   - **Password**: Escribe o genera uno (boton de varita magica)
   - **URL**: La direccion del sitio (ej. `https://github.com`)
   - **Notes**: Cualquier informacion adicional
4. Haz clic en **Save**

### Editar un entry

1. Selecciona el entry en la lista lateral
2. Haz clic en el icono de **lapiz** en la barra de herramientas
3. Modifica los campos que necesites
4. Haz clic en **Save**

### Copiar un password

Hay varias formas:

- **Desde el detalle**: Haz clic en el icono de copiar (dos cuadros) junto al campo de password
- **Atajo de teclado**: Selecciona el entry y presiona `Cmd+Shift+C`
- **Desde la barra de menu**: Haz clic en el icono de Citadel en la barra de menu y selecciona el entry

El password se copia al portapapeles y **se borra automaticamente** despues del tiempo configurado (15 segundos por defecto, configurable de 5 a 60 segundos en Settings).

### Copiar el username

- Haz clic en el icono de copiar junto al campo de username
- O usa `Cmd+Shift+U`

### Ver el password

El password esta oculto por defecto (se muestra como puntos). Para verlo, **manten presionado** el icono del ojo. Se oculta automaticamente al soltar.

### Buscar entries

Usa el campo de busqueda en la barra lateral. Citadel usa fuzzy search — no necesitas escribir el nombre exacto. Ver [seccion 9](#9-fuzzy-search) para mas detalles.

### Tips

- Siempre usa el generador de passwords — nunca inventes passwords a mano
- Agrega la URL para poder identificar rapidamente a que sitio pertenece cada entry
- Usa notas para guardar preguntas de seguridad, instrucciones de recuperacion, etc.

---

## 4. Templates

### Que son

Las templates son plantillas predefinidas que crean entries con campos personalizados para diferentes tipos de credenciales. En lugar de crear un Login generico y agregar campos manualmente, selecciona la template adecuada y los campos aparecen automaticamente.

### Como usar una template

1. Haz clic en **+** para crear un nuevo entry
2. En la parte superior veras un scroll horizontal con las templates disponibles
3. Haz clic en la que necesites
4. Los campos personalizados aparecen automaticamente
5. Llena la informacion y guarda

### Templates disponibles

#### Login
- **Para que sirve:** Credenciales clasicas de sitios web
- **Campos:** Title, Username, Password, URL, Notes (campos estandar)
- **Ejemplo real:** Tu cuenta de Netflix, Gmail, o cualquier sitio web

#### Crypto Wallet
- **Para que sirve:** Guardar de forma segura las llaves de wallets de criptomonedas
- **Campos:** Wallet Name, Address, Seed Phrase (protegido), Private Key (protegido), Network
- **Ejemplo real:** Tu wallet de MetaMask con la seed phrase de 24 palabras y la llave privada de Ethereum
- **Importante:** La seed phrase y private key son campos protegidos — siempre estan ocultos

#### Server / SSH
- **Para que sirve:** Credenciales de servidores y acceso SSH
- **Campos:** Hostname, IP Address, Port, SSH Key (protegido), Root Password (protegido), Provider
- **Ejemplo real:** Tu servidor de produccion en AWS con IP `34.201.xx.xx`, puerto 22, y la llave SSH privada

#### API Key
- **Para que sirve:** Llaves de APIs de servicios externos
- **Campos:** Service Name, API Key (protegido), API Secret (protegido), Endpoint URL, Documentation URL
- **Ejemplo real:** Tu API key de OpenAI (`sk-proj-...`) con el endpoint y link a la documentacion

#### Database
- **Para que sirve:** Credenciales de bases de datos
- **Campos:** Hostname, Port, Database Name, Connection String (protegido)
- **Ejemplo real:** Tu base de datos PostgreSQL en `db.example.com:5432`, database `myapp_production`

#### Email Account
- **Para que sirve:** Configuracion completa de cuentas de email (incluyendo servidores IMAP/SMTP)
- **Campos:** Email, IMAP Server, SMTP Server, Port, App Password (protegido)
- **Ejemplo real:** Tu cuenta de trabajo con `imap.gmail.com`, `smtp.gmail.com`, puerto 993, y un app password de Google

#### Credit Card
- **Para que sirve:** Datos de tarjetas de credito/debito
- **Campos:** Cardholder Name, Card Number (protegido), Expiry Date, CVV (protegido), Billing Address, PIN (protegido)
- **Ejemplo real:** Tu tarjeta Visa terminada en 4242, con CVV y PIN protegidos
- **Nota:** No usa campos estandar de username/password — todos los datos van en custom fields

#### Identity
- **Para que sirve:** Documentos de identidad (pasaporte, licencia, INE/CURP)
- **Campos:** Full Name, Date of Birth, ID Type, ID Number (protegido), Issuing Country, Expiry Date, Address, Phone
- **Ejemplo real:** Tu pasaporte con numero protegido, fecha de vencimiento, y direccion actual

#### Secure Note
- **Para que sirve:** Texto libre encriptado sin campos de login
- **Campos:** Solo Title y contenido de texto
- **Ejemplo real:** Instrucciones de recuperacion de tu empresa, o notas legales privadas
- **Ver:** [seccion 5](#5-secure-notes) para mas detalles

#### Recovery Codes
- **Para que sirve:** Codigos de recuperacion de 2FA de servicios importantes
- **Campos:** Service Name, Recovery Codes (protegido)
- **Ejemplo real:** Los 10 codigos de recuperacion de tu cuenta de GitHub, uno por linea

#### Software License
- **Para que sirve:** Licencias de software comprado
- **Campos:** Product Name, License Key (protegido), Email, Purchase Date, Expiry
- **Ejemplo real:** Tu licencia de Sketch con key `XXXX-XXXX-XXXX`, comprada en 2024, licencia perpetua

---

## 5. Secure Notes

### Que son

Una Secure Note es un entry especial que solo tiene titulo y contenido de texto — no tiene campos de username, password, ni URL. Es basicamente un bloc de notas encriptado.

### Cuando usar Secure Note vs Login

| Usa Secure Note cuando... | Usa Login cuando... |
|---------------------------|---------------------|
| Guardas texto libre sin credenciales | Guardas usuario y password de un sitio |
| Necesitas anotar instrucciones privadas | Necesitas copiar un password rapidamente |
| Guardas informacion legal o personal | El dato tiene una URL asociada |
| Es un recordatorio o procedimiento | Es una credencial que usas para autenticarte |

### Como crear una Secure Note

1. Haz clic en **+** para crear entry
2. Selecciona la template **Secure Note**
3. Escribe el titulo y el contenido
4. Guarda

### Tips

- En la lista de entries, las Secure Notes se identifican con una etiqueta morada "Secure Note"
- El contenido se muestra como "Content" en lugar de "Notes" para distinguirlo
- Los campos de username, password y URL no aparecen en la vista de detalle

---

## 6. Custom Fields

### Que son

Los Custom Fields son campos adicionales que puedes agregar a cualquier entry. Cada template los pre-crea, pero tambien puedes agregar los tuyos manualmente.

### Campos protegidos vs no protegidos

| Protegido (candado cerrado) | No protegido (candado abierto) |
|-----------------------------|-------------------------------|
| El valor se muestra como puntos (`........`) | El valor se muestra en texto plano |
| Ideal para: passwords, keys, PINs, seeds | Ideal para: nombres, URLs, notas |
| Se necesita accion explicita para ver | Siempre visible |

### Como agregar un campo personalizado

1. Edita el entry (icono de lapiz)
2. Desplazate hasta la seccion de campos personalizados
3. Haz clic en **+ Add Field**
4. Escribe el nombre del campo y su valor
5. Haz clic en el icono de **candado** para marcarlo como protegido si contiene informacion sensible
6. Guarda

### Como eliminar un campo

1. Edita el entry
2. Haz clic en el icono **-** (menos) junto al campo que quieres eliminar
3. Guarda

### Ejemplos de uso

- **Entry de Login + campo "Security Question":** Agrega un campo protegido con la respuesta a la pregunta de seguridad
- **Entry de Server + campo "Backup Server":** Agrega un campo no protegido con la IP del servidor de respaldo
- **Entry de API Key + campo "Rate Limit":** Agrega un campo no protegido con "1000 req/min"

---

## 7. TOTP / 2FA

### Que es

TOTP (Time-based One-Time Password) es el sistema de autenticacion de dos factores que genera codigos de 6 digitos que cambian cada 30 segundos. Es lo que apps como Google Authenticator o Authy hacen — pero Citadel lo tiene integrado.

### Para que sirve

En lugar de abrir otra app para obtener el codigo 2FA, lo tienes junto con tus credenciales en Citadel. Copias el password, copias el codigo TOTP, y listo.

### Como agregar TOTP a un entry

1. Edita el entry (icono de lapiz)
2. En el campo **TOTP URI**, pega la URI `otpauth://` del servicio
3. Guarda

**Donde conseguir la URI:** Cuando un sitio te muestra un codigo QR para configurar 2FA, generalmente hay una opcion "Can't scan? Enter manually" o "Show secret key". La URI tiene el formato:

```
otpauth://totp/Servicio:usuario@email.com?secret=BASE32SECRET&issuer=Servicio
```

Si solo tienes el secret key (ej. `JBSWY3DPEHPK3PXP`), construye la URI:

```
otpauth://totp/NombreDelServicio?secret=JBSWY3DPEHPK3PXP
```

### Como usar el codigo TOTP

1. Selecciona el entry en la lista
2. En la vista de detalle, veras un **anillo de progreso circular** con los segundos restantes
3. El codigo de 6 digitos aparece formateado como `123 456`
4. Haz clic en el boton de copiar junto al codigo
5. El anillo cambia a **rojo** cuando quedan 5 segundos o menos — espera al siguiente codigo

### Tips

- El codigo se actualiza automaticamente cada 30 segundos
- Si el anillo esta en rojo (menos de 5 segundos), espera al siguiente ciclo para evitar que expire mientras lo pegas
- El TOTP solo aparece si la URI es valida — si no ves el anillo, verifica el formato de la URI
- Guarda los **recovery codes** del servicio en un entry separado usando la template Recovery Codes

---

## 8. Favorites y Folders

### Favorites

#### Que son
Los favorites son entries marcados con una estrella para acceso rapido. Aparecen al inicio de la lista y en el menu de la barra de estado.

#### Como marcar un favorito
1. Selecciona el entry
2. Haz clic en el icono de **estrella** en la barra de herramientas
3. La estrella se llena de amarillo cuando esta activo

#### Para que sirve
- Los favoritos aparecen primero en la lista lateral
- En el **menu bar** (icono de Citadel en la barra superior), los favoritos son los entries que se muestran directamente — un clic y el password se copia
- Marca como favoritos los 5-10 passwords que usas a diario

### Folders (grupos)

#### Que son
Los folders (internamente llamados "groups") te permiten organizar entries en carpetas, como un sistema de archivos.

#### Como crear un folder
1. Al crear o editar un entry, busca la seccion **Folder**
2. Selecciona un folder existente, o elige **"New folder"**
3. Escribe la ruta del folder (ej. `Work/Email` crea "Email" dentro de "Work")
4. Guarda el entry

#### Como mover un entry a un folder
1. Edita el entry
2. Cambia el folder en el selector
3. Guarda

#### Tips de organizacion
- Usa folders como: `Personal`, `Work`, `Finance`, `Development`, `Social`
- Los folders se crean automaticamente con la ruta — `Work/Servers/Production` crea tres niveles
- Combina folders con favoritos: un entry puede estar en un folder Y ser favorito

---

## 9. Fuzzy Search

### Que es

Fuzzy search es un sistema de busqueda inteligente que encuentra entries incluso si no escribes el nombre exacto. Busca coincidencias parciales, en orden pero no necesariamente contiguas.

### Como busca

Citadel busca en multiples campos de cada entry:

- Titulo
- Username
- URL
- Notas

El algoritmo asigna puntuacion basandose en:

1. **Coincidencia exacta** — la mas alta puntuacion (ej. buscar "git" encuentra "GitHub")
2. **Coincidencia al inicio** — bonus por coincidir desde el primer caracter
3. **Subsecuencia** — los caracteres aparecen en orden pero no juntos (ej. "ghb" encuentra "**G**it**H**u**b**")
4. **Mejor campo** — si el titulo no coincide pero el username si, lo encuentra igual

### Tips para buscar mejor

- Escribe las primeras 2-3 letras del servicio — generalmente es suficiente
- Si tienes muchos entries similares, escribe parte del username para filtrar
- La busqueda es **case-insensitive** — "GITHUB", "github", "GitHub" son lo mismo
- Si no encuentras algo, prueba con el nombre de usuario en lugar del titulo

### Ejemplos

| Buscas | Encuentra |
|--------|-----------|
| `git` | GitHub, GitLab, Gitea |
| `ama` | Amazon, Amazon AWS, Gmail (si el username contiene "ama") |
| `ghb` | GitHub (subsecuencia: G-H-B) |
| `prod db` | No — la busqueda es por un solo termino. Busca "prod" o "database" |

---

## 10. Password Health / Watchtower

### Que es

Watchtower es un dashboard de seguridad que analiza todos tus passwords y te dice que deberias mejorar. Piensalo como un "chequeo medico" de tus credenciales.

### Como acceder

- Desde **Settings > Password Health Report**
- Se abre en una ventana dedicada

### Security Score

Watchtower calcula un puntaje de 0 a 100:

| Puntaje | Clasificacion | Color |
|---------|---------------|-------|
| 90-100 | Excellent | Verde |
| 70-89 | Good | Verde |
| 40-69 | Fair | Naranja |
| 0-39 | Poor | Rojo |

El puntaje empieza en 100 y se restan puntos por cada problema:

| Problema | Penalizacion |
|----------|-------------|
| Password comprometido (breach) | -15 puntos |
| Password debil | -10 puntos |
| Password reutilizado | -8 puntos |
| Password viejo (>180 dias) | -3 puntos |
| Expirando pronto (<30 dias) | -3 puntos |
| Sin TOTP/2FA | -2 puntos |
| URL con HTTP (no HTTPS) | -2 puntos |

### Categorias

#### 1. Breached Passwords (rojo)
- **Que significa:** Este password aparecio en una filtracion de datos publica
- **Que hacer:** Cambia el password **inmediatamente**. Si lo usas en otros sitios, cambialos tambien
- **Ver:** [seccion 11](#11-breach-check-hibp) para como funciona la verificacion

#### 2. Weak Passwords (rojo)
- **Que significa:** El password es corto, predecible, o no tiene suficiente variedad de caracteres
- **Que hacer:** Genera un nuevo password usando el generador de Citadel (minimo 16 caracteres)

#### 3. Reused Passwords (naranja)
- **Que significa:** Dos o mas entries usan el mismo password
- **Que hacer:** Genera passwords unicos para cada servicio. Si un sitio se compromete, los demas quedan seguros
- **Muestra:** Los nombres de los otros entries que comparten el mismo password

#### 4. Old Passwords >180 dias (amarillo)
- **Que significa:** No has cambiado el password en mas de 6 meses
- **Que hacer:** Considera actualizarlo, especialmente si el servicio es importante (banco, email principal)

#### 5. Expiring Soon <30 dias (amarillo)
- **Que significa:** El entry tiene una fecha de expiracion configurada y esta por vencer
- **Que hacer:** Renueva la credencial antes de que expire

#### 6. Missing TOTP (azul)
- **Que significa:** El entry no tiene 2FA configurado
- **Que hacer:** Si el servicio lo soporta, activa 2FA y agrega la URI TOTP al entry

#### 7. Insecure URLs — HTTP (naranja)
- **Que significa:** La URL del entry usa HTTP en lugar de HTTPS
- **Que hacer:** Actualiza la URL a HTTPS. Si el sitio no soporta HTTPS, ten precaucion extra

### Tips

- Revisa el Watchtower al menos una vez al mes
- Empieza por los problemas rojos (breaches y passwords debiles) — son los mas criticos
- No te obsesiones con llegar a 100 — un score de 80+ es excelente para la mayoria de usuarios
- Haz clic en cualquier entry en la lista para ir directamente a editarlo

---

## 11. Breach Check HIBP

### Que es

HIBP (Have I Been Pwned) es un servicio creado por Troy Hunt que recopila datos de filtraciones de seguridad publicas. Citadel puede verificar si tus passwords aparecen en alguna filtracion conocida.

### Es seguro

**Si.** Citadel usa el metodo de **k-anonymity** — tus passwords nunca salen de tu Mac.

### Como funciona k-anonymity (paso a paso)

1. Citadel toma tu password (ej. `password123`)
2. Calcula el hash SHA-1: `CBFDAC6008F9CAB4083784CBD1874F76618D2A97`
3. Envia **solo los primeros 5 caracteres** (`CBFDA`) al servidor de HIBP
4. HIBP responde con **todos** los hashes que empiezan con esos 5 caracteres (cientos o miles)
5. Citadel busca **localmente** si el resto del hash coincide
6. Si coincide, tu password fue comprometido

**Lo que el servidor de HIBP ve:** Solo `CBFDA` — que es compartido por miles de passwords diferentes. No puede saber cual es el tuyo.

**Lo que NUNCA sale de tu Mac:** Tu password, el hash completo, o cualquier dato que permita identificar tu password.

### Como usar la verificacion de breaches

1. Abre **Settings > Password Health Report** (Watchtower)
2. En la seccion "Breached Passwords", haz clic en **"Check for Breaches"**
3. La primera vez, Citadel pide tu **consentimiento** explicando que se enviaran hashes parciales
4. Acepta si estas de acuerdo
5. Citadel verifica cada password (con 200ms de pausa entre cada uno para no sobrecargar el servidor)
6. Los resultados muestran cuantas veces aparecio cada password en filtraciones

### Cache

Los resultados se guardan en cache por **24 horas**. No necesitas verificar mas de una vez al dia.

### Tips

- Si un password aparece en breaches, **no significa que tu cuenta fue hackeada** — significa que alguien, en alguna parte, uso el mismo password y ese password quedo expuesto
- Cambia cualquier password que aparezca como breached, sin importar el numero de ocurrencias
- Un password con 50,000+ ocurrencias es extremadamente comun — cambiatelo ya

---

## 12. Secure Sharing

### Que es

Secure Sharing te permite compartir credenciales con otra persona de forma encriptada, sin depender de servicios externos. Genera un link encriptado que solo puede ser descifrado por quien lo recibe.

### Como funciona tecnicamente

1. Citadel selecciona los campos que quieres compartir
2. Los encripta con **ChaChaPoly** (encriptacion autenticada de 256 bits) usando una llave aleatoria
3. Genera un link en formato `citadel://share#LLAVE#DATOS_ENCRIPTADOS`
4. La llave y los datos van **juntos en el link** — cualquiera que tenga el link puede descifrarlo

### Como enviar credenciales

1. Abre el entry que quieres compartir
2. Haz clic en el icono de **compartir** (cuadro con flecha) en la barra de herramientas
3. Selecciona los campos que quieres incluir (checkboxes)
4. Opcionalmente, establece una **fecha de expiracion**
5. Haz clic en **Create Link**
6. El link se copia automaticamente al portapapeles
7. Envia el link a la otra persona por un canal seguro (mensaje directo, Signal, etc.)

### Como recibir credenciales

1. En Citadel, ve al menu de acciones (tres puntos o "More") > **Receive Shared Entry**
2. Pega el link que te enviaron
3. Citadel descifra los datos y muestra los campos
4. Puedes ver la informacion y opcionalmente **guardarla como un nuevo entry** en tu vault

### Consideraciones de seguridad

- El link contiene la llave de desencriptacion — **trata el link como si fuera el password mismo**
- Envialo por un canal seguro (no email sin encriptar)
- Usa la opcion de expiracion para que el link deje de funcionar despues de cierto tiempo
- El link funciona offline — no necesita internet para descifrarse
- Una vez que la otra persona tiene el link, puede descifrarlo las veces que quiera (hasta que expire)

### Tips

- Nunca compartas el link por canales publicos (Slack publico, email sin encriptar, SMS)
- Si la informacion es muy sensible, envia la llave por un canal y los datos por otro (split knowledge)
- Usa expiracion corta (24 horas o menos) para credenciales temporales

---

## 13. Multiple Vaults

### Que es

Citadel soporta multiples vaults — archivos `.kdbx` independientes, cada uno con su propio master password. Esto te permite separar tus credenciales personales de las de trabajo, o tener vaults compartidos con equipo.

### Vaults por defecto

La primera vez que abres Citadel, se crean dos vaults:

- **Personal** (`~/.citadel/personal.kdbx`) — para tus credenciales personales
- **Work** (`~/.citadel/work.kdbx`) — para credenciales laborales

Si existia un vault legacy (`vault.kdbx`), se registra automaticamente como "Personal".

### Como cambiar de vault

1. En la barra de herramientas, haz clic en el **nombre del vault activo** (icono de disco externo)
2. Se despliega un menu con todos tus vaults
3. Selecciona el vault al que quieres cambiar
4. El vault actual se bloquea automaticamente
5. Ingresa el master password del nuevo vault

### Como crear un vault nuevo

1. Cambia a un vault que no tenga archivo creado (o crea uno nuevo desde el vault switcher si la opcion esta disponible)
2. En la pantalla de Lock, selecciona **"Create New Vault"**
3. Escribe el nombre y master password
4. El nuevo vault queda registrado y activo

### Como renombrar o eliminar un vault del registro

Los vaults se gestionan desde el VaultRegistry. Eliminar un vault del registro **no borra el archivo** — solo lo quita de la lista de Citadel. Puedes volver a importarlo despues.

### Tips

- Usa un vault separado para credenciales de trabajo — si cambias de empleo, puedes entregar o eliminar solo ese vault
- Cada vault tiene su propio master password — puedes usar passwords diferentes
- Los vaults son archivos `.kdbx` independientes — puedes abrir cualquiera en KeePassXC u otra app compatible

---

## 14. Backup y Recovery

### Tipos de backup

Citadel ofrece **tres** niveles de proteccion:

#### 1. Backup normal (archivo .kdbx)

- **Que es:** Una copia del archivo de tu vault actual
- **Como hacerlo:** Toolbar > More Actions > **Backup Vault** > Selecciona donde guardarlo
- **Formato:** Archivo `.kdbx` identico al original
- **Como restaurar:** Simplemente importa el archivo `.kdbx` o reemplaza el vault

#### 2. Full Backup encriptado (archivo .ctdl)

- **Que es:** Un bundle encriptado que contiene **todos** tus vaults, protegido con un password de backup independiente
- **Como hacerlo:**
  1. Toolbar > More Actions > **Full Vault Backup**
  2. Escribe un **backup password** (puede ser diferente al master password)
  3. Confirma el password
  4. Selecciona donde guardar el archivo `.ctdl`
- **Formato:** Archivo `.ctdl` con magic bytes + ChaChaPoly encryption
- **Que contiene:** Todos tus vaults + keyfiles + manifest con checksums SHA-256
- **Ventaja:** Un solo archivo protege todo. Ideal para guardar en USB, disco externo, o caja fuerte

#### 3. Verificar backup

- **Que es:** Valida que un archivo `.ctdl` esta intacto y puede ser restaurado
- **Como hacerlo:** Toolbar > More Actions > **Verify Backup** > Selecciona el `.ctdl` > Ingresa backup password
- **Que verifica:** Descifra el bundle, valida el manifest, verifica checksums de cada archivo

#### 4. Restaurar desde backup

- **Como hacerlo:**
  1. Toolbar > More Actions > **Restore from Backup**
  2. Selecciona el archivo `.ctdl`
  3. Ingresa el backup password
  4. Los vaults se restauran al directorio `~/.citadel/`
  5. Los vaults restaurados se registran automaticamente

### Recovery Sheet

- **Que es:** Un documento imprimible con instrucciones para abrir tu vault en caso de que Citadel no este disponible
- **Como generarlo:** Settings > **Print Recovery Sheet**
- **Que incluye:**
  - La ruta de tu archivo vault
  - Instrucciones paso a paso para abrir el vault en KeePassXC
  - Instrucciones paso a paso para abrir el vault en Strongbox
  - Nota sobre backups encriptados `.ctdl`
- **Que NO incluye:** Tu master password ni tu backup password (debes guardarlos por separado)

### Estrategia de backup recomendada

1. **Semanal:** Crea un Full Backup encriptado (`.ctdl`)
2. **Mensual:** Verifica que el backup se puede restaurar
3. **Siempre:** Ten el Recovery Sheet impreso en un lugar seguro
4. **Guarda backups en:** USB cifrado, disco externo, o caja fuerte fisica — NO en servicios de nube sin encriptar
5. **El backup password:** Guardalo en un lugar separado al backup (ej. escrito en papel en una caja fuerte diferente)

---

## 15. Menu Bar

### Que es

Citadel pone un icono en la barra de menu de macOS (junto al reloj, WiFi, etc.) para acceso rapido a tus passwords sin abrir la ventana principal.

### Que muestra el icono

- **Si el vault esta bloqueado:** Muestra "Citadel — Locked" con opcion de "Open Citadel"
- **Si el vault esta desbloqueado:** Muestra tus entries organizados

### Como copiar un password rapido

1. Haz clic en el icono de Citadel en la barra de menu
2. **Favoritos** aparecen primero — haz clic en uno para copiar su password instantaneamente
3. Para entries no favoritos, ve a **"All Entries"** > selecciona el entry > **"Copy Password"** o **"Copy Username"**

### Funciones disponibles

- **Copiar password** con un clic (favoritos)
- **Copiar password o username** desde submenus (todos los entries)
- **Cambiar vault** (si tienes multiples vaults)
- **Bloquear vault** sin abrir la ventana
- **Abrir Citadel** (trae la ventana principal al frente)

### Limite

Se muestran hasta **20 entries** en favoritos y 20 en "All Entries" para mantener el menu manejable.

### Tips

- Marca como favoritos los passwords que copias varias veces al dia
- Usa el menu bar cuando solo necesitas copiar un password — es mas rapido que abrir la app completa
- El menu bar funciona incluso cuando la ventana principal esta cerrada

---

## 16. Keyboard Shortcuts

### Lista completa

| Atajo | Accion |
|-------|--------|
| `Cmd+N` | Crear nuevo entry |
| `Cmd+,` | Abrir Settings |
| `Cmd+L` | Bloquear vault |
| `Cmd+Shift+C` | Copiar password del entry seleccionado |
| `Cmd+Shift+U` | Copiar username del entry seleccionado |

### Notas

- Los atajos solo funcionan cuando el vault esta desbloqueado (excepto que no hay accion posible cuando esta bloqueado)
- `Cmd+Shift+C` y `Cmd+Shift+U` requieren que haya un entry seleccionado en la lista
- Todos los atajos aparecen en el menu **Vault** de la barra de menus de macOS

---

## 17. Seguridad

### Que protege Citadel

- **Passwords en reposo:** Encriptados con AES-256 en formato KDBX 4, protegidos con Argon2id
- **Passwords en memoria:** Limpieza activa de memoria al bloquear (`.resetBytes`), prevencion de core dumps
- **Portapapeles:** Se limpia automaticamente despues de N segundos
- **Pantalla:** Seguridad de ventana aplicada para prevenir capturas
- **Disco:** El directorio `~/.citadel/` tiene `.metadata_never_index` para prevenir indexacion de Spotlight
- **Archivos biometricos:** Permisos `0600` (solo tu usuario)
- **Guardar datos:** Atomic save con validacion antes de sobreescribir, mas snapshot `.prev` de respaldo
- **Audit log:** Registro de acciones (unlock, lock, cambio de password, etc.)
- **Recuperacion de crash:** Si el vault se corrompe durante un save, se recupera automaticamente del `.prev` o `.tmp`
- **Deteccion de nube:** Advertencia si el vault esta en un directorio sincronizado a la nube

### Que NO protege Citadel

- **Keyloggers:** Si tu Mac tiene malware que captura lo que escribes, Citadel no puede prevenir eso
- **Acceso fisico prolongado:** Si alguien tiene acceso fisico a tu Mac desbloqueado por tiempo indefinido, puede eventualmente extraer datos de la memoria
- **Ingenieria social:** Si alguien te convence de darle tu master password, Citadel no puede ayudarte
- **Backup passwords debiles:** Si tu backup password del `.ctdl` es debil, el backup es vulnerable
- **Screenshots por malware:** Aunque Citadel intenta prevenir capturas de pantalla, malware con permisos de accesibilidad podria evadirlo
- **Sincronizacion de nube:** Citadel advierte pero no impide guardar el vault en carpetas sincronizadas

### Comparacion con otros gestores

| Caracteristica | Citadel | 1Password | Bitwarden |
|----------------|---------|-----------|-----------|
| Datos almacenados | Solo local | Nube propia | Nube/self-host |
| Formato | KDBX 4 (estandar) | Propietario | Propietario |
| Codigo abierto | Si | No | Si |
| Precio | Gratis | $3-5/mes | Gratis-$3/mes |
| Funciona offline | Siempre | Parcial | Parcial |
| Puedes leer tus datos sin la app | Si (KeePassXC, etc.) | No | Parcial |
| Sincronizacion multi-dispositivo | Manual/tu responsabilidad | Automatica | Automatica |
| Recuperacion si la empresa cierra | No aplica (local) | Incierto | Export posible |
| Auditoria del codigo | Posible (local) | No posible | Posible |

**En resumen:** Citadel es para usuarios que quieren control total sobre sus datos. 1Password y Bitwarden son mejores si necesitas sincronizacion automatica entre dispositivos. Citadel es mejor si priorizas soberania de datos y no dependencia de servicios externos.

---

## 18. KeePassXC / iPhone

### Por que importa

Tu vault de Citadel es un archivo `.kdbx` estandar. Esto significa que **no dependes de Citadel para acceder a tus datos**. Cualquier app compatible con KDBX 4 puede abrirlo.

### Como abrir tu vault en KeePassXC (Mac/Windows/Linux)

1. Descarga KeePassXC desde [keepassxc.org](https://keepassxc.org)
2. Abre KeePassXC
3. Selecciona **File > Open Database**
4. Navega a `~/.citadel/` y selecciona tu archivo `.kdbx` (ej. `personal.kdbx`)
5. Ingresa tu master password
6. Si usas keyfile, seleccionalo tambien
7. Tus entries apareceran en KeePassXC

**Nota:** KeePassXC soporta Argon2id, TOTP, custom fields, y todos los features de KDBX 4.

### Como usar tu vault en iPhone con KeePassium

1. Copia tu archivo `.kdbx` a tu iPhone (via AirDrop, iCloud Drive, o cable USB)
2. Descarga **KeePassium** desde la App Store (gratis, con opcion premium)
3. Abre KeePassium
4. Selecciona **"Add Database"** y navega al archivo `.kdbx`
5. Ingresa tu master password
6. KeePassium puede auto-fill passwords en Safari y otras apps via el sistema AutoFill de iOS

**Alternativas en iPhone:**

- **Strongbox** — Otra app excelente para KDBX en iPhone/iPad
- **KeePassDX** — Para Android

### Sincronizacion manual

Si quieres tener el vault actualizado en tu iPhone:

1. Copia el `.kdbx` a iCloud Drive, Dropbox, o cualquier servicio de archivos
2. Abre el archivo desde KeePassium/Strongbox en el iPhone
3. **Importante:** No edites el vault desde dos dispositivos al mismo tiempo — puede causar conflictos

### Tips

- Imprime el **Recovery Sheet** de Citadel para tener instrucciones paso a paso siempre a mano
- KeePassXC es tu "plan B" definitivo — si algo pasa con Citadel, tus datos estan a salvo
- Verifica al menos una vez que puedes abrir tu vault en KeePassXC

---

## 19. Troubleshooting

### Olvide mi master password

**No hay forma de recuperarlo.** Citadel no tiene servidores ni mecanismo de reset.

**Que puedes intentar:**

1. Intenta variaciones comunes (mayusculas, espacios, acentos)
2. Si tienes un **backup** (`.kdbx` o `.ctdl`), intenta con el password que recuerdes haber usado cuando lo creaste
3. Si configuraste un **keyfile**, asegurate de usar el correcto
4. Revisa si tienes el password anotado en un lugar seguro

**Prevencion para el futuro:**

- Imprime el Recovery Sheet
- Guarda tu master password escrito en papel en una caja fuerte
- Crea backups regulares

### El vault no abre (archivo corrupto)

1. **Recuperacion automatica:** Citadel intenta automaticamente restaurar desde `.prev` o `.tmp` si el archivo principal esta corrupto
2. **Backup manual:** Si hay un archivo `.kdbx.prev` en `~/.citadel/`, puedes renombrarlo a `.kdbx` manualmente:
   ```bash
   cd ~/.citadel
   cp personal.kdbx personal.kdbx.broken
   cp personal.kdbx.prev personal.kdbx
   ```
3. **Desde backup:** Si tienes un Full Backup (`.ctdl`), restauralo desde Citadel > More Actions > Restore from Backup
4. **KeePassXC:** Intenta abrir el archivo en KeePassXC — a veces puede leer archivos que Citadel no puede

### Touch ID no funciona

1. **Verifica que esta activado:** Settings > Security > Touch ID debe estar ON
2. **72 horas:** Si pasaron mas de 72 horas desde tu ultimo login con password, necesitas ingresar el password completo una vez
3. **Cambio de password:** Si cambiaste tu master password, Touch ID se desactivo. Re-activalo en Settings
4. **Hardware:** Verifica que Touch ID funciona en otros lugares (desbloquear el Mac, App Store, etc.)
5. **Re-enrollment:** Desactiva Touch ID en Settings y vuelvelo a activar

### El vault esta en una carpeta sincronizada a la nube

Citadel muestra una advertencia si detecta que `~/.citadel/` esta dentro de:

- iCloud Drive (`~/Library/Mobile Documents`)
- Dropbox (`~/Dropbox`)
- Google Drive (`~/Google Drive`)
- OneDrive (`~/OneDrive`)

**Riesgo:** Ediciones simultaneas desde multiples dispositivos pueden causar perdida de datos silenciosa.

**Solucion:** Mueve tu vault a una ubicacion local no sincronizada, como el default `~/.citadel/`.

### Las passwords expiradas aparecen al abrir

Esto es una funcion de seguridad. Citadel revisa si alguna entry tiene fecha de expiracion vencida o proxima (7 dias) y te alerta al desbloquear.

**Que hacer:** Revisa cada entry mencionado y actualiza el password o extiende la fecha de expiracion.

### El score de Watchtower es bajo

No te alarmes — el score penaliza por precaucion. Prioriza:

1. **Primero:** Cambia passwords comprometidos (breached) — son el riesgo mas alto
2. **Segundo:** Cambia passwords debiles
3. **Tercero:** Elimina passwords reutilizados
4. **Con calma:** Activa 2FA donde puedas, actualiza URLs a HTTPS

### Auto-lock bloquea muy rapido / muy lento

Ajusta el timeout en **Settings > Auto-lock timeout** (slider de 1 a 30 minutos). El default es 5 minutos.

---

## Apendice: Ubicaciones de archivos

| Archivo | Ubicacion | Proposito |
|---------|-----------|-----------|
| Vault principal | `~/.citadel/personal.kdbx` | Tus passwords encriptados |
| Vault de trabajo | `~/.citadel/work.kdbx` | Vault secundario |
| Snapshot de respaldo | `~/.citadel/*.kdbx.prev` | Copia automatica pre-save |
| Archivos biometricos | `~/.citadel/.bio-nonce`, `.bio-blob` | Touch ID (permisos 0600) |
| Audit log | `~/.citadel/audit.log` | Registro de acciones |
| Preferencias | `~/Library/Preferences/` (UserDefaults) | KDF preset, vault registry, auto-lock |
| No-index | `~/.citadel/.metadata_never_index` | Previene indexacion de Spotlight |

---

*Citadel — Tus passwords, tu control.*
