import 'dart:convert';
import 'dart:io';

// 1. EVENTOS
final Set<String> _eventKeys = {
  'name', 'author', 'flavor', 'about',
  'optiona', 'optionb', 'optionc',
  'successa', 'successb', 'successc',
  'failurea', 'failureb', 'failurec',
  'a_locked', 'b_locked', 'c_locked',
};

// 2. ENEMIGOS
final Set<String> _enemyKeys = {
  'name', 'subtitle', 'author', 'intro',
  'hit01', 'hit02', 'hit03',
};

// 3. PERSONAJES
final Set<String> _characterKeys = {
  'name', 'author',
  'name_a', 'name_b',
  'menu_tag', 'menu_desc', 'bio',
};

// 4. MISTERIOS
final Set<String> _mysteryKeys = {
  'name', 'author', 'description',
  'flavor', 'tags',
  'text_one', 'text_two', 'text_thr', 'text_fou',
  'location', // solo se usa para Misterios
  'one_txt', 'two_txt', 'thr_txt', 'fou_txt', 'fiv_txt', 'six_txt', 'sev_txt', 'eig_txt', 'nin_txt', 'ten_txt',
  'end_title', 'end_txt', 'end_txta', 'end_txtb', 'end_txtc', 'end_txtd'
};

// Lista de valores de 'location' que son código interno y no deben traducirse.
final Set<String> _nonTranslatableLocations = {
  'school', 'seaside', 'mansion', 'downtown', 'hospital', 'forest', 'village',
  'apartment', 'atorasu', 'ithotu', 'athyola', 'gozu', 'ygothaeg', 'schoolhospital',
  'seasideforest', 'global', 'otherworld', 'herald', 'kturufu', 'zhectast', 'ehzhal', 'linked'
};

// 5. FALLBACK
// Si un archivo .ito está mal formateado y no tiene etiqueta principal, usamos
// todas las claves, pero 'location' se filtrará usando la lista de arriba.
final Set<String> _fallbackKeys = {
  ..._eventKeys,
  ..._enemyKeys,
  ..._characterKeys,
  ..._mysteryKeys,
};

final RegExp _itoLineRegex = RegExp(r'^([a-zA-Z0-9_]+)="(.*)"$');

void main() async {
  print("--- WOH Mod Translator ---");

  final modsDir = Directory('mods');
  final l10nDir = Directory('l10n');

  if (!modsDir.existsSync()) modsDir.createSync();
  if (!l10nDir.existsSync()) l10nDir.createSync();

  while (true) {
    print("\nSelecciona una opción:");
    print("1. Extraer textos de /mods a JSON en /l10n");
    print("2. Inyectar traducciones desde /l10n a /mods");
    print("3. Salir");
    stdout.write("> ");

    final choice = stdin.readLineSync();

    if (choice == '1') {
      await _extractToL10n(modsDir, l10nDir);
    } else if (choice == '2') {
      await _injectToMods(modsDir, l10nDir);
    } else if (choice == '3') {
      break;
    } else {
      print("Opción no válida.");
    }
  }
}

/// Extrae el último segmento de una ruta física.
String _basename(String path) => path.split(Platform.pathSeparator).last;

/// Retorna el nombre de un archivo eliminando su ruta y su extensión.
String _basenameWithoutExtension(String path) {
  final base = _basename(path);
  final lastDotIndex = base.lastIndexOf('.');
  return lastDotIndex != -1 ? base.substring(0, lastDotIndex) : base;
}

/// Lee el contenido de un archivo manejando posibles problemas de codificación (BOM/UTF-8)
Future<List<String>> _readLinesSafely(File file) async {
  final bytes = await file.readAsBytes();
  String content = utf8.decode(bytes, allowMalformed: true);

  // Elimina el BOM (Byte Order Mark) si está presente al inicio del archivo
  if (content.startsWith('\uFEFF')) {
    content = content.substring(1);
  }

  // Divide por saltos de línea compatibles con Windows (\r\n) o Linux (\n)
  return content.split(RegExp(r'\r?\n'));
}

/// Escanea las carpetas de mods, detecta archivos .ito y genera o actualiza
/// archivos JSON en el directorio de localización con las claves traducibles.
Future<void> _extractToL10n(Directory modsDir, Directory l10nDir) async {
  final modFolders = modsDir.listSync().whereType<Directory>().toList();

  if (modFolders.isEmpty) {
    print("No hay mods en la carpeta /mods/.");
    return;
  }

  for (final modFolder in modFolders) {
    final modId = _basename(modFolder.path);
    final jsonFile = File('${l10nDir.path}${Platform.pathSeparator}$modId.json');

    Map<String, dynamic> manifest = jsonFile.existsSync()
        ? jsonDecode(await jsonFile.readAsString())
        : {
            "mod_id": modId,
            "mod_name": "Nombre del Mod",
            "author_original": "",
            "translator": "",
            "files": <String, dynamic>{}
          };

    manifest["files"] ??= <String, dynamic>{};
    final filesMap = manifest["files"] as Map<String, dynamic>;

    final itoFiles = modFolder
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.ito'));

    int keysExtracted = 0;

    for (final itoFile in itoFiles) {
      final relativePath = itoFile.path
          .replaceFirst(modFolder.path + Platform.pathSeparator, '')
          .replaceAll(r'\', '/');

      filesMap[relativePath] ??= <String, dynamic>{};
      final fileData = filesMap[relativePath] as Map<String, dynamic>;

      final lines = await _readLinesSafely(itoFile);

      // Asumimos el grupo comodín por defecto
      Set<String> activeKeys = _fallbackKeys;

      for (final line in lines) {
        final trimmedLine = line.trim();

        // Detectar el tipo de archivo dinámicamente y asignar el set correcto
        if (trimmedLine == '[event]') {
          activeKeys = _eventKeys;
        } else if (trimmedLine == '[enemy]') {
          activeKeys = _enemyKeys;
        } else if (trimmedLine == '[character]') {
          activeKeys = _characterKeys;
        } else if (trimmedLine == '[mystery]') {
          activeKeys = _mysteryKeys;
        }

        final match = _itoLineRegex.firstMatch(trimmedLine);
        if (match != null) {
          final key = match.group(1)!;
          final value = match.group(2)!;

          if (key == 'author' && manifest["author_original"] == "") {
            manifest["author_original"] = value;
          }
          if (key == 'name' && manifest["mod_name"] == "Nombre del Mod") {
            manifest["mod_name"] = value;
          }

          if (activeKeys.contains(key)) {
            // EXCEPCIÓN: Si la clave es 'location', verificar que su VALOR
            // no sea uno de los códigos internos del juego.
            if (key == 'location' && _nonTranslatableLocations.contains(value)) {
              // Es un código interno, no hacer nada y continuar con la siguiente línea.
              continue; 
            }

            // Si pasa el filtro, es una clave traducible.
            if (!fileData.containsKey(key)) {
              fileData[key] = {"original": value, "l10n": ""};
              keysExtracted++;
            } else if (fileData[key]["original"] != value) {
              // El autor actualizó el mod, se sobrescribe el original para que concuerde.
              fileData[key]["original"] = value;
              print("  [AVISO] El texto original de '$key' en '$relativePath' ha cambiado tras una actualización.");
            }
          }
        }
      }
    }

    await jsonFile.writeAsString(JsonEncoder.withIndent('  ').convert(manifest));
    print("Mod '$modId': $keysExtracted nuevas claves extraídas.");
  }
}

/// Lee los archivos JSON de localización e inyecta las traducciones existentes
/// de vuelta a los archivos .ito correspondientes en las carpetas de los mods.
Future<void> _injectToMods(Directory modsDir, Directory l10nDir) async {
  final jsonFiles = l10nDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList();

  if (jsonFiles.isEmpty) {
    print("No hay archivos JSON en /l10n/.");
    return;
  }

  for (final jsonFile in jsonFiles) {
    final modId = _basenameWithoutExtension(jsonFile.path);
    final modFolder = Directory('${modsDir.path}${Platform.pathSeparator}$modId');

    if (!modFolder.existsSync()) {
      print("No se encontró la carpeta del mod '$modId' en /mods/. Saltando...");
      continue;
    }

    final Map<String, dynamic> manifest = jsonDecode(await jsonFile.readAsString());
    final Map<String, dynamic> filesMap = manifest["files"] ?? <String, dynamic>{};

    int filesModified = 0;
    int warnings = 0;

    for (final relativePath in filesMap.keys) {
      final itoFile = File('${modFolder.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}');

      if (!itoFile.existsSync()) {
        print("  [ERROR] No se encuentra el archivo $relativePath en el mod.");
        continue;
      }

      final Map<String, dynamic> translations = filesMap[relativePath];
      List<String> newLines = [];
      bool modified = false;

      final lines = await _readLinesSafely(itoFile);

      for (final line in lines) {
        final match = _itoLineRegex.firstMatch(line.trim());

        if (match != null) {
          final key = match.group(1)!;

          if (translations.containsKey(key)) {
            final jsonTranslation = translations[key]["l10n"]?.toString() ?? "";

            if (jsonTranslation.trim().isNotEmpty) {
              final originalValue = match.group(2)!;
              final jsonOriginal = translations[key]["original"]?.toString() ?? "";

              if (originalValue != jsonOriginal) {
                print("\n  [ADVERTENCIA] Discrepancia en $modId -> $relativePath -> Clave: '$key'");
                print("    El Mod dice: $originalValue");
                print("    El JSON dice: $jsonOriginal");
                print("    ¿Aplicar traducción de todos modos? (s/n): ");

                if (stdin.readLineSync()?.toLowerCase() == 's') {
                  newLines.add('$key="$jsonTranslation"');
                  modified = true;
                } else {
                  newLines.add(line);
                }
                warnings++;
              } else {
                newLines.add('$key="$jsonTranslation"');
                modified = true;
              }
            } else {
              newLines.add(line);
            }
          } else {
            newLines.add(line);
          }
        } else {
          newLines.add(line);
        }
      }

      if (modified) {
        // Guardar de vuelta con saltos de línea estándar de Windows, que usa WoH
        await itoFile.writeAsString(newLines.join('\r\n'));
        filesModified++;
      }
    }

    print("Mod '$modId': $filesModified archivos actualizados. ($warnings advertencias)");
  }
}
