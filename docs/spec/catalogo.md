# Catálogo de MixMeister (biblioteca) — especificación

Dónde está, en un Mac con MixMeister Studio 7.8:

```
~/Library/Application Support/MixMeister Technology/MixMeister Engine Studio 7/catalog.mdb
```

(Fusion: `MixMeister Engine 7`.) Es una base **SQLite de Core Data** (modo WAL: van con ella
`catalog.mdb-wal` y `catalog.mdb-shm`). El modelo está en `core-data.md`. MixMeister 8 la lee en
solo lectura a partir de una copia hecha con la API de copia de SQLite, que incluye lo pendiente
del WAL, así que nunca toca la base original.

## ZCATALOG — una fila por fichero de música

| Columna | Significado | Ejemplo / regla |
|---|---|---|
| Z_PK, ZCATALOGID | identificador | |
| ZFILENAME | ruta completa | `/Users/…/CD/001/Alexia -Summer is Crazy-.mp3` |
| ZMUSICFILEID | **identificador del audio**, 16 bytes en hex | igual que `TRKH+8` de las listas `.mmp` |
| ZSONGTITLE, ZARTISTNAME, ZALBUMNAME, ZGENRE, ZCOMPOSER, ZLABEL, ZCOMMENTS, ZYEAR, ZUSER1, ZUSER2 | etiquetas | columnas de la biblioteca |
| ZTRACKNUMBER, ZRATING | número de pista, valoración (0-5) | |
| ZBPM | tempo (float) | 137.0957 |
| ZBEATCOUNT | «Number of Beats in Music File» (Edit Tag) | 0 = automático |
| ZKEY | nota: 0 = C, 1 = C#, … 11 = B | 5 → F |
| ZKEYFLAGS | bit 0: tonalidad conocida | en esta biblioteca todas las detectadas se muestran como menores (F m, F#m, A m) |
| ZSAMPLECOUNT, ZSAMPLERATE | duración en muestras | 10 732 032 / 44 100 = 4:03 |
| ZBITRATE | bits por segundo | 128 000 |
| ZFILETYPE | 1 = MP3 (resto, pendiente) | |
| ZDATEADDED, ZFILELASTWRITTEN, ZLASTUPDATED | fechas Core Data: segundos desde 2001-01-01 | −63114076800 = «nunca» |
| ZDEFAULTTRACKPRESET | Tweak por defecto (→ ZTRACKPRESET) | |
| ZPENDINGUPDATE, ZPENDINGDEFAULTMIXCLEAR | trabajo pendiente | |
| ZTHUMBNAIL | miniatura (BLOB) | |

## Otras tablas

- **ZCATEGORY** (ZCATEGORYNAME, ZCATEGORYGLOBALID) y **Z_1CATEGORY** (pista ↔ categoría).
- **ZTRACKPRESET** — los *Tweaks*: ZTRACKPRESETNAME, ZTRACKPRESETDATA (BLOB), ZSMALLFINGERPRINT, ZCATALOG.
- **ZMONTAGEPRESET** — transiciones personalizadas: ZNAME, ZTRANSITIONID, ZTRANSITIONLENGTH, ZSTYLEID, ZFLAGS.
- **ZPROFILEWORKITEM** — cola de análisis.

## Preferencias

`~/Library/Preferences/com.mixmeister.MixMeisterStudio.plist`: orden y anchura de cada columna de
la biblioteca y de la lista (`Catalog<Col>ColumnOrder/Width`, −1 = oculta), número de carriles de
la línea de tiempo, tipo de ajuste a la rejilla, configuración de salida, carpeta de plots,
listas recientes y posiciones de los divisores. MixMeister 8 las importa la primera vez para
arrancar con la misma disposición.
