import 'dart:convert';
import 'dart:io';

// 1. EVENTOS
final Set<String> _eventKeys = {
  'name', 'flavor', 'about',
  'optiona', 'optionb', 'optionc',
  'successa', 'successb', 'successc',
  'failurea', 'failureb', 'failurec',
  'a_locked', 'b_locked', 'c_locked',
};

// 2. ENEMIGOS
final Set<String> _enemyKeys = {
  'name', 'subtitle', 'intro',
  'hit01', 'hit02', 'hit03',
};

// 3. PERSONAJES
final Set<String> _characterKeys = {
  'name', 'name_a', 'name_b',
  'menu_tag', 'menu_desc', 'bio',
};

// 4. MISTERIOS
final Set<String> _mysteryKeys = {
  'name', 'description', 'flavor', 'tags',
  'text_one', 'text_two', 'text_thr', 'text_fou',
  'location', // solo se usa para Misterios
  'one_txt', 'two_txt', 'thr_txt', 'fou_txt', 'fiv_txt', 'six_txt', 'sev_txt', 'eig_txt', 'nin_txt', 'ten_txt',
  'end_title', 'end_txt', 'end_txta', 'end_txtb', 'end_txtc', 'end_txtd'
};

// Claves que representan RUTAS de archivos
final Set<String> _pathKeys = {
  // Eventos
  'image', 'load_sound', 'trigger_event', 'trigger_enemy',
  // Enemigos
  'art01', 'art02',
  // Personajes
  'sprite_icon', 'sprite_back', 'sprite_house', 'portrait_a', 'portrait_b',
  'sprite_chibi', 'low_stamina', 'low_reason', 'ritual_mask', 'karukosa_mask',
  'crestfallen_mask', 'cursed_signs', 'broken_nose', 'insmasu_look',
  'slit_mouth', 'hunger', 'event_a', 'event_b', 'event_c', 'event_d', 'event_e',
  // Misterios
  'art', 'background', 'end_img', 'mystery_sound', 'combat_sound',
  'one_frc', 'two_frc', 'thr_frc', 'fou_frc', 'fiv_frc',
  'six_frc', 'sev_frc', 'eig_frc', 'nin_frc', 'ten_frc'
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

  if (!modsDir.existsSync()) {
    modsDir.createSync();
  }
  if (!l10nDir.existsSync()) {
    l10nDir.createSync();
  }

  while (true) {
    print("\nSelecciona una opción:");
    print("1. Extraer textos de /mods a JSON en /l10n");
    print("2. Inyectar traducciones desde /l10n a /mods");
    print("3. Construir paquete unificado y traducido");
    print("4. Salir");
    stdout.write("> ");

    final choice = stdin.readLineSync();

    if (choice == '1') {
      await _extractToL10n(modsDir, l10nDir);
    } else if (choice == '2') {
      await _injectToMods(modsDir, l10nDir);
    } else if (choice == '3') {
      await _buildUnifiedPack(modsDir, l10nDir);
    } else if (choice == '4') {
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
  String content = utf8.decode(await file.readAsBytes(), allowMalformed: true);

  // Elimina el BOM (Byte Order Mark) oculto si está presente
  if (content.startsWith('\uFEFF')) {
    content = content.substring(1);
  }

  // Divide por saltos de línea compatibles con Windows (\r\n) o Linux (\n)
  return content.split(RegExp(r'\r?\n'));
}

/// Compara binariamente dos archivos para saber si son idénticos
bool _areFilesIdentical(File f1, File f2) {
  if (f1.lengthSync() != f2.lengthSync()) {
    return false;
  }
  final b1 = f1.readAsBytesSync();
  final b2 = f2.readAsBytesSync();
  for (int i = 0; i < b1.length; i++) {
    if (b1[i] != b2[i]) {
      return false;
    }
  }
  return true;
}

/// Copia recursivamente el contenido de un directorio a otro
void _copyDirectorySync(Directory source, Directory destination) {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }
  for (var entity in source.listSync(recursive: false)) {
    final newPath = '${destination.path}${Platform.pathSeparator}${_basename(entity.path)}';
    if (entity is Directory) {
      var newDirectory = Directory(newPath);
      newDirectory.createSync();
      _copyDirectorySync(entity, newDirectory);
    } else if (entity is File) {
      entity.copySync(newPath);
    }
  }
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

    // Preservar traducciones previas si el archivo ya existe
    Map<String, dynamic> existingData = jsonFile.existsSync()
        ? jsonDecode(await jsonFile.readAsString())
        : {};

    // Crear el manifest para forzar el orden de las claves en el JSON
    Map<String, dynamic> manifest = {
      "mod_id": modId,
      "mod_name": existingData["mod_name"] ?? "",
      "mod_url": existingData["mod_url"] ??
          (RegExp(r'^\d+$').hasMatch(modId)
              ? "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
              : ""),
      "authors": existingData["authors"] ?? <String>[],
      "translator": existingData["translator"] ?? "",
      "files": existingData["files"] ?? <String, dynamic>{}
    };

    // Extraemos las colecciones para modificarlas por referencia sin y no reasignarlas
    final authorsList = manifest["authors"] as List<dynamic>;
    final normalizedAuthors = authorsList.map((a) => a.toString().toLowerCase()).toSet();
    final filesMap = manifest["files"] as Map<String, dynamic>;

    final itoFiles = modFolder
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.ito'));

    int keysExtracted = 0;
    int warnings = 0;
    String? firstItemName;

    for (final itoFile in itoFiles) {
      final relativePath = itoFile.path
          .replaceFirst(modFolder.path + Platform.pathSeparator, '')
          .replaceAll(r'\', '/');

      filesMap[relativePath] ??= <String, dynamic>{};
      final fileData = filesMap[relativePath] as Map<String, dynamic>;

      final lines = await _readLinesSafely(itoFile);
      Set<String> activeKeys = _fallbackKeys;

      for (final line in lines) {
        final trimmedLine = line.trim();

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
            final trimmedValue = value.trim();

            if (key == 'author' && trimmedValue.isNotEmpty) {
              final lowerAuthor = trimmedValue.toLowerCase();
              if (!normalizedAuthors.contains(lowerAuthor)) {
                normalizedAuthors.add(lowerAuthor);
                authorsList.add(trimmedValue);
              }
          }

          if (key == 'name' && firstItemName == null && trimmedValue.isNotEmpty) {
            firstItemName = trimmedValue;
          }

          if (activeKeys.contains(key)) {
            if (key == 'location' && _nonTranslatableLocations.contains(value)) {
              continue;
            }

            if (!fileData.containsKey(key)) {
              fileData[key] = {"original": value, "l10n": ""};
              keysExtracted++;
            } else if (fileData[key]["original"] != value) {
              fileData[key]["original"] = value;
              print("  [AVISO] El texto original de '$key' en '$relativePath' ha cambiado.");
              warnings++;
            }
          }
        }
      }
    }

    if (manifest["mod_name"] == "") {
      manifest["mod_name"] = (itoFiles.length == 1 && firstItemName != null) ? firstItemName : modId;
    }

    await jsonFile.writeAsString(JsonEncoder.withIndent('  ').convert(manifest));
    print("Mod '$modId': $keysExtracted nuevas claves extraídas. ($warnings advertencias)");
  }
}

/// Lee los archivos JSON de localización e inyecta las traducciones existentes
/// de vuelta a los archivos .ito correspondientes. Permite sobrescribir la 
/// carpeta original o crear una copia segura en un nuevo directorio.
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

  print("\n¿Deseas sobrescribir los archivos originales en la carpeta /mods?");
  print("Si eliges 'n', se creará una copia segura de los mods en /l10n y se aplicarán los cambios ahí.");
  stdout.write("(s/n)> ");
  final bool overwrite = (stdin.readLineSync()?.toLowerCase() ?? 'n') == 's';

  final Directory targetBaseDir = overwrite ? modsDir : Directory('l10n');
  if (!targetBaseDir.existsSync()) {
    targetBaseDir.createSync();
  }

  for (final jsonFile in jsonFiles) {
    final modId = _basenameWithoutExtension(jsonFile.path);
    final originalModFolder = Directory('${modsDir.path}${Platform.pathSeparator}$modId');

    if (!originalModFolder.existsSync()) {
      print("No se encontró la carpeta del mod original '$modId'. Omitiendo...");
      continue;
    }

    final workingModFolder = Directory('${targetBaseDir.path}${Platform.pathSeparator}$modId');

    if (!overwrite) {
      if (workingModFolder.existsSync()) {
        workingModFolder.deleteSync(recursive: true);
      }
      _copyDirectorySync(originalModFolder, workingModFolder);
    }

    final Map<String, dynamic> manifest = jsonDecode(await jsonFile.readAsString());
    final Map<String, dynamic> filesMap = manifest["files"] ?? <String, dynamic>{};

    int filesModified = 0;
    int warnings = 0;

    for (final relativePath in filesMap.keys) {
      final itoFile = File('${workingModFolder.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}');

      if (!itoFile.existsSync()) {
        print("  [ERROR] No se encuentra el archivo $relativePath en el mod.");
        warnings++;
        continue;
      }

      final Map<String, dynamic> translations = filesMap[relativePath];
      List<String> newLines = [];
      bool modified = false;

      final lines = await _readLinesSafely(itoFile);

      for (final line in lines) {
        final match = _itoLineRegex.firstMatch(line.trim());

        if (match != null) {
          final String key = match.group(1)!;
          if (translations.containsKey(key)) {
            final String originalValue = match.group(2)!;
            final String jsonTranslation = translations[key]["l10n"]?.toString() ?? "";

            if (jsonTranslation.trim().isNotEmpty) {
              final String jsonOriginal = translations[key]["original"]?.toString() ?? "";
              if (jsonOriginal.isNotEmpty && originalValue != jsonOriginal) {
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
    
    print("Mod '$modId': $filesModified archivos inyectados en ${overwrite ? "/mods" : "/l10n"}. ($warnings advertencias)");
  }
}

/// Analiza todos los mods en busca de colisiones de archivos, resuelve las
/// rutas internas, aplica las traducciones y genera un paquete unificado en
/// la carpeta de salida, opcionalmente instalándolo de forma automática.
Future<void> _buildUnifiedPack(Directory modsDir, Directory l10nDir) async {
  final buildDir = Directory('build');
  if (buildDir.existsSync()) {
    buildDir.deleteSync(recursive: true);
  }
  buildDir.createSync();

  final modFolders = modsDir.listSync().whereType<Directory>().toList();
  if (modFolders.isEmpty) {
    print("No hay mods para compilar.");
    return;
  }

  Map<String, File> deployedFiles = {};
  Map<String, String> remappedPaths = {}; 

  print("Analizando colisiones y dependencias...");
  for (final modDir in modFolders) {
    final modId = _basename(modDir.path);
    final files = modDir.listSync(recursive: true).whereType<File>();

    for (final file in files) {
      final relPath = file.path
          .replaceFirst(modDir.path + Platform.pathSeparator, '')
          .replaceAll('\\', '/');
      String targetPath = relPath;

      if (deployedFiles.containsKey(targetPath)) {
        final existingFile = deployedFiles[targetPath]!;
        if (!_areFilesIdentical(existingFile, file)) {
          final ext = targetPath.contains('.')
              ? targetPath.substring(targetPath.lastIndexOf('.'))
              : '';
          final name = targetPath.contains('.')
              ? targetPath.substring(0, targetPath.lastIndexOf('.'))
              : targetPath;
          targetPath = '${name}_$modId$ext';
          remappedPaths['$modId|$relPath'] = targetPath;
        }
      }
      deployedFiles[targetPath] = file;
    }
  }

  print("Construyendo carpeta unificada /build...");
  int totalMods = 0;
  int totalWarnings = 0;

  for (final modDir in modFolders) {
    final modId = _basename(modDir.path);
    final l10nFile = File('${l10nDir.path}${Platform.pathSeparator}$modId.json');
    Map<String, dynamic>? translations;
    int modWarnings = 0;

    if (l10nFile.existsSync()) {
      translations = jsonDecode(l10nFile.readAsStringSync())['files'];
    }

    final files = modDir.listSync(recursive: true).whereType<File>();
    for (final file in files) {
      final relPath = file.path
          .replaceFirst(modDir.path + Platform.pathSeparator, '')
          .replaceAll('\\', '/');
      final finalRelPath = remappedPaths['$modId|$relPath'] ?? relPath;
      final targetFile = File(
          '${buildDir.path}${Platform.pathSeparator}${finalRelPath.replaceAll('/', Platform.pathSeparator)}');
      targetFile.parent.createSync(recursive: true);

      if (file.path.endsWith('.ito')) {
        List<String> newLines = [];
        final fileTranslations = translations?[relPath];
        final topLevelFolder = relPath.split('/').first;
        final lines = await _readLinesSafely(file);

        for (final line in lines) {
          final match = _itoLineRegex.firstMatch(line.trim());
          if (match != null) {
            final key = match.group(1)!;
            String value = match.group(2)!;

            // 1. Aplicar Traducción
            if (fileTranslations != null && fileTranslations.containsKey(key)) {
              final String jsonTranslation = fileTranslations[key]['l10n']?.toString() ?? '';

              if (jsonTranslation.trim().isNotEmpty) {
                final String jsonOriginal = fileTranslations[key]['original']?.toString() ?? '';
                // Al ser un proceso batch, aplicamos sin preguntar pero dejamos log de advertencia
                if (jsonOriginal.isNotEmpty && value != jsonOriginal) {
                  print("  [ADVERTENCIA] Discrepancia detectada en $modId -> $relPath -> Clave: '$key'. Aplicando traducción de todos modos.");
                  modWarnings++;
                }
                value = jsonTranslation;
              }
            }

            // 2. Resolver Rutas Internas (Anti-colisión)
            if (_pathKeys.contains(key) && value.trim().isNotEmpty) {
              if (!value.contains('.') && (key == 'mystery_sound' || key == 'combat_sound')) {
                // Es un sonido interno (ej. 'computer'), lo ignoramos
              } else {
                final normalizedValue = value.replaceAll('\\', '/');
                final fullLookupPath = '$topLevelFolder/$normalizedValue';
                final lookupKey = '$modId|$fullLookupPath';

                if (remappedPaths.containsKey(lookupKey)) {
                  String newPath = remappedPaths[lookupKey]!;
                  if (newPath.startsWith('$topLevelFolder/')) {
                    newPath = newPath.substring(topLevelFolder.length + 1);
                  }
                  value = newPath.replaceAll('/', '\\');
                }
              }
            }
            newLines.add('$key="$value"');
          } else {
            newLines.add(line);
          }
        }
        targetFile.writeAsStringSync(newLines.join('\r\n'));
      } else {
        file.copySync(targetFile.path);
      }
    }
    totalMods++;
    totalWarnings += modWarnings;
    if (modWarnings > 0) {
      print("Mod '$modId' empaquetado. ($modWarnings advertencias en esta carpeta)");
    }
  }

  print("¡Construcción finalizada! $totalMods mods unificados en la carpeta /build. (Total de advertencias: $totalWarnings)");

  print("\n¿Deseas instalar el paquete unificado directamente en el juego (Windows AppData)?");
  stdout.write("(s/n)> ");
  if (stdin.readLineSync()?.toLowerCase() == 's') {
    _installToAppData(buildDir);
  }
}

/// Copia el contenido de la carpeta de construcción unificada directamente
/// al directorio de datos locales del juego en Windows (AppData/Local).
void _installToAppData(Directory buildDir) {
  final appData = Platform.environment['LOCALAPPDATA'];
  if (appData == null) {
    print("No se pudo detectar LOCALAPPDATA. Esta función solo está disponible en Windows.");
    return;
  }

  final wohDir = Directory('$appData${Platform.pathSeparator}wohgame');

  print("Copiando archivos unificados al directorio oficial del juego (${wohDir.path})...");
  _copyDirectorySync(buildDir, wohDir);
  print("Tu contenido está listo para jugarse.");
}
