# Comandos para publicar en ECR Public

Repositorio existente: `public.ecr.aws/e8b7p3v6/puentestecnologicos/wp-allinone`.

En PowerShell, cargar el helper actualizado antes del incluido en Docker Desktop:

```powershell
$env:Path = "$env:USERPROFILE\.docker\bin;$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin;$env:Path"
docker build -t wp-allinone:latest .
docker tag wp-allinone:latest public.ecr.aws/e8b7p3v6/puentestecnologicos/wp-allinone:latest
docker push public.ecr.aws/e8b7p3v6/puentestecnologicos/wp-allinone:latest
```

## Autenticación en Windows

Se instaló Amazon ECR Credential Helper 0.12.0 en
`%USERPROFILE%\.docker\bin\docker-credential-ecr-login.exe` y se configuró
`%USERPROFILE%\.docker\config.json` con esta entrada:

```json
{
  "credHelpers": {
    "public.ecr.aws": "ecr-login"
  }
}
```

Al configurar otra máquina, combinar esa entrada con las opciones existentes.
El helper utiliza la sesión AWS y obtiene el token al ejecutar `docker push`;
no se necesita `aws ecr-public get-login-password | docker login`.
Si la sesión AWS expiró, renovarla con `aws login`.

Esto evita el error de Windows Credential Manager
`The stub received bad data.` al guardar el token de ECR. El helper 0.8.0
incluido en esta instalación de Docker Desktop no pudo usar el perfil con
`login_session`; la versión 0.12.0 se verificó con la sesión actual.

Referencia: [Amazon ECR Credential Helper](https://github.com/awslabs/amazon-ecr-credential-helper#configuration).

### Error `error saving credentials ... not implemented`

Con `credHelpers.public.ecr.aws=ecr-login`, ejecutar `docker login` intenta
guardar el token mediante el helper. Su operación `Add()` no está implementada:
el helper obtiene credenciales temporales automáticamente cuando se hace push/pull.
Mantener la configuración existente y omitir el comando de login manual:

```powershell
$env:Path = "$env:USERPROFILE\.docker\bin;$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin;$env:Path"
docker tag wp-allinone:latest public.ecr.aws/e8b7p3v6/puentestecnologicos/wp-allinone:latest
docker push public.ecr.aws/e8b7p3v6/puentestecnologicos/wp-allinone:latest
```

La ruta del helper actualizado debe ir primero: esta máquina también incluye
una versión anterior dentro de Docker Desktop. Si la sesión AWS expiró,
renovarla con `aws login` antes de reintentar el push. No es necesario eliminar
`credHelpers` ni guardar contraseñas manualmente en `config.json`.

Referencia del error: [implementación de Add()](https://github.com/awslabs/amazon-ecr-credential-helper/blob/main/ecr-login/ecr.go).

# Construir imagen sin Cache
docker build --no-cache -t wp-allinone . 

## Idioma de WordPress

`WP_LOCALE` sigue usando `es_ES` (español de España) por defecto. Se puede
cambiar con `docker run -e WP_LOCALE=es_MX ... wp-allinone`, por ejemplo.

El arranque descarga el core en `en_US` e instala y activa por separado el
paquete de idioma solicitado durante la instalación inicial. Esto evita
`Error: The requested locale (es_ES) was not found.` cuando la API de
WordPress ofrece una versión nueva del core solo en `en_US`, aunque su
traducción `es_ES` ya esté disponible. La opción `WPLANG` por sí sola no
garantiza que los archivos de traducción estén instalados.

Después de modificar `start.sh`, reconstruir la imagen y recrear el
contenedor con las mismas variables y volúmenes; reiniciar el contenedor
anterior no incorpora el script nuevo. No eliminar los volúmenes de datos.

Para verificar el idioma de un contenedor en ejecución (sustituir `NOMBRE`):

```sh
docker exec NOMBRE wp --allow-root --path=/var/www/html option get WPLANG
docker exec NOMBRE wp --allow-root --path=/var/www/html language core is-installed es_ES
```

Si WordPress ya estaba instalado pero faltan sus traducciones:

```sh
docker exec NOMBRE wp --allow-root --path=/var/www/html language core install es_ES --activate
```

La descarga del paquete de idioma requiere acceso a WordPress.org. Si falla,
el arranque informa del error y se detiene.

