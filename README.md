# WOH Mods ES - Traductor de Mods de World of Horror

Entorno de trabajo para extraer, traducir e inyectar textos al español en mods de *World of Horror* (`.ito`).

## ¿Cómo funciona?
Los mods originales no tienen soporte multidioma. Esta herramienta extrae los textos traducibles a un archivo `.json` que funciona como manifiesto y archivo de localización. Luego, el script reemplaza los textos originales en los archivos `.ito` usando el JSON.

## Instrucciones de uso

1. Clona este repositorio y ejecuta `dart pub get`.
2. Descarga los mods de la Workshop de Steam (o de otra fuente) y pega sus carpetas (ej. `3237724411`) dentro de la carpeta `/mods/` de este proyecto.
3. Ejecuta el script:
   ```bash
   dart run bin/woh_mod_translator.dart
   ```

### Opciones del Menú
* **1. Extraer/Actualizar JSON:** Escanea la carpeta `/mods/` y genera (o actualiza) archivos en la carpeta `/l10n/`. 
  * **Si un mod se actualiza:** El script actualizará el texto original guardado bajo la clave `"original"` en el JSON para reflejar los cambios del autor, pero **nunca** borrará las traducciones en la clave `"l10n"`.
* **2. Inyectar Traducción:** Lee los archivos `.json` en `/l10n/` y sobrescribe los textos en la carpeta `/mods/`. 
  * *Nota:* El script compara el texto actual del `.ito` con el `"original"` guardado en el JSON. Si el autor actualizó un texto (y olvidaste extraer los cambios), el script te avisará en la terminal para que decidas si aplicar la traducción antigua de todos modos o mantener el texto original del autor.

## Contribuir (Pull Requests)
Cualquiera puede ayudar, solo necesitas generar los JSON, traducir los campos `"l10n": ""` en la carpeta `l10n/` y abrir un Pull Request en este repositorio. **No subas los archivos originales de los mods (la carpeta `/mods/` está ignorada).**
