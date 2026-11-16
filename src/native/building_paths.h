#ifndef MLE_BUILDING_PATHS_H
#define MLE_BUILDING_PATHS_H
#include <stdint.h>
#include <string.h>

/* UE 5.5 shipping layout. FSoftObjectPtr has an 8-byte weak cache followed
 * by a 32-byte FSoftObjectPath (two 8-byte FNames, then a 16-byte FString).
 * Top-level asset names require no FString assignment or heap ownership.
 */
static int building_preview_path(unsigned char *row, uint32_t label, const unsigned char *path) {
    unsigned char before[8], after[32], original[40];
    uint32_t actual_label, package, asset;
    int32_t source_length, target_length;
    memcpy(&actual_label, row + 0xc, 4);
    memcpy(&package, path, 4);
    memcpy(&asset, path + 8, 4);
    memcpy(&source_length, path + 24, 4);
    memcpy(&target_length, row + 0x178, 4);
    if (!label || actual_label != label || !package || !asset ||
            source_length || target_length) return 0;
    memcpy(before, row + 0x150, sizeof(before));
    memcpy(after, row + 0x180, sizeof(after));
    memcpy(original, row + 0x158, sizeof(original));
    memset(row + 0x158, 0, 8);
    memcpy(row + 0x160, path, 16);
    if (memcmp(row + 0x160, path, 16) || memcmp(before, row + 0x150, sizeof(before)) ||
            memcmp(after, row + 0x180, sizeof(after)) || memcmp(original + 24, row + 0x170, 16)) {
        memcpy(row + 0x158, original, sizeof(original));
        return 0;
    }
    return 1;
}

/* FConstructionBP holds a hard UClass immediately before its soft class.
 * Native construction streaming reads the soft path. Keep the hard class,
 * row label, and empty subpath storage intact.
 */
static int building_construction_path(unsigned char *row, uint32_t label, const unsigned char *path) {
    uint64_t hard_class;
    uint32_t actual_label, target_length;
    uint32_t source_names[4], target_names[4], source_length;
    memcpy(&hard_class, row + 0x8, 8);
    memcpy(&actual_label, row + 0x38, 4);
    memcpy(&target_length, row + 0x30, 4);
    memcpy(&source_length, path + 24, 4);
    memcpy(source_names, path, sizeof(source_names));
    memcpy(target_names, row + 0x18, sizeof(target_names));
    if (!hard_class || !label || actual_label != label || target_length || source_length ||
            !source_names[0] || !source_names[2]) return 0;
    if ((target_names[0] || target_names[1] || target_names[2] || target_names[3]) &&
            memcmp(source_names, target_names, sizeof(source_names))) return 0;
    memset(row + 0x10, 0, 8);
    memcpy(row + 0x18, source_names, sizeof(source_names));
    return !memcmp(row + 0x18, path, sizeof(source_names));
}
/* Texture references use the same owned top-level soft-object layout. */
static int building_texture_path(unsigned char *row, uint32_t label, unsigned int offset, const unsigned char *path) {
    uint32_t actual_label, length, package, asset, source_length;
    memcpy(&actual_label, row + 0xc, 4);
    memcpy(&length, row + offset + 32, 4);
    memcpy(&package, path, 4); memcpy(&asset, path + 8, 4); memcpy(&source_length, path + 24, 4);
    if ((offset != 0x18 && offset != 0x40 && offset != 0x68) ||
            !label || actual_label != label || length || source_length || !package || !asset) return 0;
    memset(row + offset, 0, 8); memcpy(row + offset + 8, path, 16);
    return !memcmp(row + offset + 8, path, 16);
}
#endif
