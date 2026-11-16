/* Exact-build native building paths, rollback journal and upgrade dispatcher. */
#include <windows.h>
#include <wincrypt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "building_paths.h"

typedef struct { unsigned char *data; int32_t count, capacity; } Array;
static HMODULE self_module;
static int verified_executable;
static int module_matches(HMODULE module, const unsigned char expected[32]) {
    WCHAR path[MAX_PATH]; HCRYPTPROV provider = 0; HCRYPTHASH hash = 0;
    HANDLE file = INVALID_HANDLE_VALUE;
    unsigned char block[65536], digest[32]; DWORD received = 0, size = sizeof(digest); int matched = 0;
    if (!GetModuleFileNameW(module, path, MAX_PATH) ||
            !CryptAcquireContextW(&provider, NULL, NULL, PROV_RSA_AES, CRYPT_VERIFYCONTEXT) ||
            !CryptCreateHash(provider, CALG_SHA_256, 0, 0, &hash)) goto finish;
    file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) goto finish;
    for (;;) {
        if (!ReadFile(file, block, sizeof(block), &received, NULL)) goto finish;
        if (!received) break;
        if (!CryptHashData(hash, block, received, 0)) goto finish;
    }
    matched = CryptGetHashParam(hash, HP_HASHVAL, digest, &size, 0) && size == sizeof(digest) && !memcmp(digest, expected, sizeof(digest));
finish:
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    if (hash) CryptDestroyHash(hash);
    if (provider) CryptReleaseContext(provider, 0);
    return matched;
}
static int exact_executable(void) {
    if (verified_executable) return verified_executable == 1;
    verified_executable = -1;
    static const unsigned char game[32] = {0x56,0x04,0x51,0xdf,0x38,0xcd,0x91,0x13,0x40,0x26,0xc2,0x5b,0x69,0x53,0x94,0x49,0xc5,0x70,0xf3,0x16,0x3e,0x33,0xbc,0x8c,0x45,0xb4,0xdc,0x20,0xb6,0x95,0x2c,0xee};
    static const unsigned char loader[32] = {0x68,0x0a,0x02,0x68,0x90,0xab,0xb4,0xd0,0xdf,0x22,0x11,0x25,0x1f,0x8d,0xef,0xc1,0x68,0x1a,0x58,0x42,0x75,0xf1,0x52,0x1d,0xcc,0x0f,0xe3,0x0a,0xf4,0x80,0x00,0x6f};
    HMODULE ue4ss = GetModuleHandleW(L"UE4SS.dll");
    if (ue4ss && module_matches(NULL, game) && module_matches(ue4ss, loader)) verified_executable = 1;
    return verified_executable == 1;
}
static int readable(const void *pointer, size_t size) {
    MEMORY_BASIC_INFORMATION info;
    uintptr_t address = (uintptr_t)pointer;
    return pointer && VirtualQuery(pointer, &info, sizeof(info)) && info.State == MEM_COMMIT &&
        !(info.Protect & (PAGE_NOACCESS | PAGE_GUARD)) && address + size >= address &&
        address + size <= (uintptr_t)info.BaseAddress + info.RegionSize;
}
static int array_valid(const Array *array, size_t width, int maximum) {
    return readable(array, sizeof(*array)) && array->count >= 0 && array->count <= maximum &&
        array->capacity >= array->count && array->capacity <= maximum &&
        (!array->count || readable(array->data, (size_t)array->count * width));
}
#define MAX_BINDINGS 4096
#define MAX_JOURNALS 4096
typedef struct {
    unsigned char *row;
    unsigned int label, offset;
    unsigned char before[40], after[40];
} BindingSnapshot;
typedef struct { unsigned long long token; unsigned int count; BindingSnapshot *entries; } Journal;
static Journal journals[MAX_JOURNALS];
static unsigned long long next_token;

static int writable(unsigned char *row, unsigned int size) {
    MEMORY_BASIC_INFORMATION info;
    return readable(row, size) && VirtualQuery(row, &info, sizeof(info)) &&
        (info.Protect & (PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY));
}
static int mailbox(char *request, char *response) {
    char path[MAX_PATH];
    if (!GetModuleFileNameA(self_module, path, sizeof(path))) return 0;
    char *slash = strrchr(path, '\\');
    if (!slash) return 0;
    *slash = 0;
    return snprintf(request, MAX_PATH, "%s\\..\\Control\\building-native.request", path) < MAX_PATH &&
        snprintf(response, MAX_PATH, "%s\\..\\Control\\building-native.response", path) < MAX_PATH;
}
__declspec(dllexport) int mle_building_check_profile(void *lua_state) {
    (void)lua_state;
    char request[MAX_PATH], response[MAX_PATH], magic[32], extra;
    unsigned long long nonce;
    if (!mailbox(request, response)) return 0;
    FILE *in = fopen(request, "r"), *out = fopen(response, "w");
    if (!out) { if (in) fclose(in); return 0; }
    if (in && fscanf(in, "%31s %llu", magic, &nonce) == 2 &&
            !strcmp(magic, "MLE_BUILDING_PROFILE_1") && nonce && nonce <= 9007199254740991ULL &&
            fscanf(in, " %c", &extra) != 1 && exact_executable()) fprintf(out, "OK %llu 1\n", nonce);
    else fprintf(out, "ERROR Unsupported game or UE4SS profile\n");
    if (in) fclose(in);
    fclose(out); return 0;
}
__declspec(dllexport) int mle_building_paths(void *lua_state) {
    (void)lua_state;
    char request[MAX_PATH], response[MAX_PATH], magic[32], extra;
    unsigned long long nonce = 0, token = 0;
    unsigned int count = 0, kind = 0;
    if (!mailbox(request, response)) return 0;
    FILE *in = fopen(request, "r"), *out = fopen(response, "w");
    if (!out) { if (in) fclose(in); return 0; }
    BindingSnapshot *entries = NULL;
    int success = 0;
    if (!in || fscanf(in, "%31s %llu", magic, &nonce) != 2 || !nonce || nonce > 9007199254740991ULL || !exact_executable()) goto finish;
    if (!strcmp(magic, "MLE_BUILDING_UNDO_1")) {
        if (fscanf(in, "%llu", &token) != 1 || fscanf(in, " %c", &extra) == 1) goto finish;
        for (unsigned int slot = 0; slot < MAX_JOURNALS; slot++) {
            Journal *journal = &journals[slot];
            if (journal->token != token || !journal->entries) continue;
            for (unsigned int i = 0; i < journal->count; i++) {
                BindingSnapshot *entry = &journal->entries[i];
                unsigned int label_offset = entry->offset == 0x10 ? 0x38 : 0xc;
                if (!writable(entry->row, entry->offset + 40) ||
                        *(uint32_t *)(entry->row + label_offset) != entry->label ||
                        memcmp(entry->row + entry->offset, entry->after, 40)) goto finish;
            }
            for (unsigned int i = 0; i < journal->count; i++) {
                BindingSnapshot *entry = &journal->entries[i];
                memcpy(entry->row + entry->offset, entry->before, 40);
            }
            free(journal->entries); memset(journal, 0, sizeof(*journal)); success = 1; break;
        }
        goto finish;
    }
    if (strcmp(magic, "MLE_BUILDING_PATHS_1") || fscanf(in, "%u %u", &kind, &count) != 2 ||
            kind > 4 || !count || count > MAX_BINDINGS) goto finish;
    unsigned int slot;
    for (slot = 0; slot < MAX_JOURNALS; slot++) if (!journals[slot].entries) break;
    if (slot == MAX_JOURNALS) goto finish;
    entries = calloc(count, sizeof(*entries));
    if (!entries) goto finish;
    unsigned char (*paths)[32] = calloc(count, 32);
    if (!paths) goto finish;
    unsigned int parsed = 0;
    for (; parsed < count; parsed++) {
        unsigned long long address, source_address; unsigned int package, asset;
        BindingSnapshot *entry = &entries[parsed];
        if (fscanf(in, "%llu %u %llu %u %u", &address, &entry->label, &source_address, &package, &asset) != 5 || !entry->label || (!source_address && (!package || !asset))) break;
        entry->row = (unsigned char *)(uintptr_t)address; entry->offset = kind == 0 ? 0x158 : kind == 1 ? 0x10 : kind == 2 ? 0x18 : kind == 3 ? 0x40 : 0x68;
        if (!writable(entry->row, kind == 1 ? 0x40 : 0x1a0)) break;
        for (unsigned int j = 0; j < parsed; j++) if (entries[j].row == entry->row) goto parsed_failed;
        if (source_address) {
            const unsigned char *source = (const unsigned char *)(uintptr_t)source_address;
            if (!readable(source, 32) || *(uint32_t *)(source + 24) || !*(uint32_t *)source || !*(uint32_t *)(source + 8)) break;
            memcpy(paths[parsed], source, 16);
        } else {
            memcpy(paths[parsed], &package, 4); memcpy(paths[parsed] + 8, &asset, 4);
        }
        memcpy(entry->before, entry->row + entry->offset, 40);
    }
parsed_failed:
    if (parsed != count || fscanf(in, " %c", &extra) == 1) { free(paths); goto finish; }
    for (unsigned int i = 0; i < count; i++) {
        int written = kind == 0 ? building_preview_path(entries[i].row, entries[i].label, paths[i]) :
            kind == 1 ? building_construction_path(entries[i].row, entries[i].label, paths[i]) :
            building_texture_path(entries[i].row, entries[i].label, entries[i].offset, paths[i]);
        if (!written) {
            for (unsigned int j = 0; j < i; j++) memcpy(entries[j].row + entries[j].offset, entries[j].before, 40);
            free(paths); goto finish;
        }
        memcpy(entries[i].after, entries[i].row + entries[i].offset, 40);
    }
    free(paths);
    token = ++next_token;
    journals[slot] = (Journal){token, count, entries}; entries = NULL; success = 1;
finish:
    free(entries);
    if (success) fprintf(out, "OK %llu %llu\n", nonce, token);
    else fprintf(out, "ERROR Building native request refused\n");
    if (in) fclose(in);
    fclose(out); return 0;
}

#include "building_upgrades.h"
__declspec(dllexport) int mle_building_upgrade_unbind(void *lua_state) {
    (void)lua_state;
    char request[MAX_PATH], response[MAX_PATH], magic[32], extra;
    unsigned long long nonce; int source, action;
    if (!mailbox(request, response)) return 0;
    FILE *in = fopen(request, "r"), *out = fopen(response, "w");
    if (!out) { if (in) fclose(in); return 0; }
    int success = 0;
    if (in && fscanf(in, "%31s %llu %d %d", magic, &nonce, &source, &action) == 4 &&
            !strcmp(magic, "MLE_UPGRADE_UNBIND_1") && nonce && nonce <= 9007199254740991ULL &&
            fscanf(in, " %c", &extra) != 1 && exact_executable()) {
        for (unsigned int i = 0; i < 256; i++) {
            if (upgrade_bindings[i].source == source && upgrade_bindings[i].action == action) {
                memset(&upgrade_bindings[i], 0, sizeof(upgrade_bindings[i])); success = 1; break;
            }
        }
    }
    if (success) fprintf(out, "OK %llu 0\n", nonce);
    else fprintf(out, "ERROR Upgrade unbind refused\n");
    if (in) fclose(in);
    fclose(out); return 0;
}
BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) self_module = module;
    return TRUE;
}
