#ifndef MLE_BUILDING_UPGRADES_H
#define MLE_BUILDING_UPGRADES_H

/* Exact-build native entry adapter for owned building upgrade actions.
 * The generic engine type-change routine owns the actor rebuild and preserves
 * the existing native construction/material transport path.
 */
typedef void (*BuildingUpgradeExec)(void *, void *, void *);
static BuildingUpgradeExec building_upgrade_original;
static void **building_upgrade_exec_slot;
typedef struct {
    int32_t source, target, action;
    unsigned char *source_row, *target_row, *action_row;
    uint32_t source_label, target_label;
} BuildingUpgrade;
static BuildingUpgrade upgrade_bindings[256];
static BuildingUpgrade *active_upgrade;
#define building_upgrade_source active_upgrade->source
#define building_upgrade_target active_upgrade->target
#define building_upgrade_action active_upgrade->action
#define building_upgrade_source_row active_upgrade->source_row
#define building_upgrade_target_row active_upgrade->target_row
#define building_upgrade_action_row active_upgrade->action_row
#define building_upgrade_source_label active_upgrade->source_label
#define building_upgrade_target_label active_upgrade->target_label

static int building_upgrade_validate_rows(unsigned char *source, uint32_t source_label,
        unsigned char *target, uint32_t target_label, unsigned char *action, int target_id) {
    if (!readable(source, 0x1a0) || !readable(target, 0x1a0) || !readable(action, 0x88)) return 0;
    const Array *name = (Array *)(action + 8);
    return *(uint32_t *)(source + 0xc) == source_label && *(uint32_t *)(target + 0xc) == target_label &&
        array_valid(name, sizeof(WCHAR), 256) && name->count > 1 &&
        *(int32_t *)(action + 0x80) == target_id;
}

static int building_upgrade_rows(void) {
    return building_upgrade_validate_rows(building_upgrade_source_row, building_upgrade_source_label,
        building_upgrade_target_row, building_upgrade_target_label, building_upgrade_action_row, building_upgrade_target);
}

static int building_upgrade_begin(unsigned char *building, unsigned char *base) {
    if (!readable(building, 0x900) || !building_upgrade_rows() ||
            *(int32_t *)(building + 0x3b8) != building_upgrade_source ||
            !building[0x3c1] || building[0x3a1] || building[0x388] ||
            !readable(*(void **)(building + 0x2c8), 0x10)) return 0;
    Array *done = (Array *)(building + 0x430);
    if (!array_valid(done, 4, 4096)) return 0;
    for (int i = 0; i < done->count; i++)
        if (((int32_t *)done->data)[i] == building_upgrade_action) return 0;

    Array reasons = {0};
    int accepted = ((unsigned char (*)(void *, int, Array *))(base + 0x4d2b340))(building, building_upgrade_action, &reasons);
    if (reasons.data) ((void (*)(void *))(base + 0x1128900))(reasons.data);
    if (!accepted) return 0;

    int old_count = done->count;
    done->count++;
    if (done->count > done->capacity)
        ((void (*)(Array *, int))(base + 0x10dd950))(done, old_count);
    ((int32_t *)done->data)[old_count] = building_upgrade_action;

    /* UE 5.5 Shipping TFunction<void()> layout, matching BeginUpgrade's own
     * inline callback. The native vtable clones its 16-byte lambda payload.
     * The callback installs the custom action's costs exactly once.
     */
    __attribute__((aligned(16))) unsigned char callback[64] = {0};
    *(void **)(callback + 0) = base + 0x4cff270;
    *(void **)(callback + 32) = base + 0x7db8610;
    *(void **)(callback + 40) = building;
    *(int32_t *)(callback + 48) = building_upgrade_action;
    callback[52] = 1;
    ((void (*)(void *, int, void *))(base + 0x4cfb710))(building, building_upgrade_target, callback);
    return 1;
}

static void building_upgrade_exec(void *context, void *frame_pointer, void *result) {
    unsigned char *building = context, *frame = frame_pointer;
    int matched_source = 0;
    if (readable(building, 0x3bc)) {
        for (unsigned int i = 0; i < 256; i++)
            if (upgrade_bindings[i].source == *(int32_t *)(building + 0x3b8)) matched_source = 1;
    }
    if (!matched_source) {
        building_upgrade_original(context, frame_pointer, result);
        return;
    }
    unsigned char *base = (unsigned char *)GetModuleHandleA(NULL);
    /* Consume the single int32 EUpgradeType exactly as the pinned native
     * wrapper does, including compiled-in and Blueprint bytecode callers.
     */
    int32_t action = 0;
    if (!readable(frame, 0x90) || !readable(result, 1)) return;
    if (*(void **)(frame + 0x20)) {
        ((void (*)(void *, void *, void *))(base + 0x14898e0))(frame, *(void **)(frame + 0x18), &action);
    } else {
        unsigned char *property = *(unsigned char **)(frame + 0x88);
        if (!readable(property, 0x20)) return;
        *(void **)(frame + 0x88) = *(void **)(property + 0x18);
        ((void (*)(void *, void *, void *))(base + 0x1489910))(frame, &action, property);
    }
    if (*(unsigned char **)(frame + 0x20)) (*(unsigned char **)(frame + 0x20))++;
    active_upgrade = NULL;
    for (unsigned int i = 0; i < 256; i++) {
        if (upgrade_bindings[i].source == *(int32_t *)(building + 0x3b8) && upgrade_bindings[i].action == action) {
            active_upgrade = &upgrade_bindings[i]; break;
        }
    }
    if (!active_upgrade) {
        /* Parameters have been consumed once. Call the identical native body,
         * preserving all native behavior for other actions on this actor.
         */
        *(unsigned char *)result = ((unsigned char (*)(void *, int))(base + 0x4cfc2f0))(context, action) != 0;
        return;
    }
    *(unsigned char *)result = building_upgrade_begin(building, base) != 0;
}

__declspec(dllexport) int mle_building_upgrade_bind(void *lua_state) {
    (void)lua_state;
    char path[MAX_PATH], request[MAX_PATH], response[MAX_PATH], magic[32], extra;
    unsigned long long nonce, function_address, source_row, target_row, action_row;
    int source, target, action;
    unsigned int source_label, target_label;
    BuildingUpgrade snapshot = {0}; int binding_changed = 0, binding_success = 0;
    if (!GetModuleFileNameA(self_module, path, sizeof(path))) return 0;
    char *slash = strrchr(path, '\\');
    if (!slash) return 0;
    *slash = 0;
    if (snprintf(request, sizeof(request), "%s\\..\\Control\\building-upgrade.request", path) >= (int)sizeof(request) ||
            snprintf(response, sizeof(response), "%s\\..\\Control\\building-upgrade.response", path) >= (int)sizeof(response)) return 0;
    FILE *in = fopen(request, "r"), *out = fopen(response, "w");
    if (!out) { if (in) fclose(in); return 0; }
    if (!in || fscanf(in, "%31s %llu %llu %d %d %d %llu %u %llu %u %llu", magic, &nonce,
            &function_address, &source, &target, &action, &source_row, &source_label,
            &target_row, &target_label, &action_row) != 11 || fscanf(in, " %c", &extra) == 1 ||
            strcmp(magic, "MLE_BUILDING_UPGRADE_1") || !nonce || nonce > 9007199254740991ULL ||
            source <= 0 || target <= 0 || source == target || action < 46 || action > 4096 ||
            !source_label || !target_label || !exact_executable()) {
        fprintf(out, "ERROR Invalid owned building upgrade binding\n"); goto finish_upgrade;
    }
    unsigned char *base = (unsigned char *)GetModuleHandleA(NULL);
    unsigned char *function = (unsigned char *)(uintptr_t)function_address;
    if (!readable(function, 0x100)) {
        fprintf(out, "ERROR Invalid BeginUpgrade function object\n"); goto finish_upgrade;
    }
    void **slot = NULL;
    int matches = 0;
    for (int offset = 0x90; offset < 0x100; offset += 8) {
        void **candidate = (void **)(function + offset);
        if (*candidate == base + 0x4af08d0 || *candidate == (void *)building_upgrade_exec) {
            slot = candidate;
            matches++;
        }
    }
    if (matches != 1 || (building_upgrade_exec_slot && (slot != building_upgrade_exec_slot ||
            *slot != (void *)building_upgrade_exec))) {
        fprintf(out, "ERROR BeginUpgrade executable binding changed\n"); goto finish_upgrade;
    }
    if (!building_upgrade_validate_rows((unsigned char *)(uintptr_t)source_row, source_label,
            (unsigned char *)(uintptr_t)target_row, target_label, (unsigned char *)(uintptr_t)action_row, target)) {
        fprintf(out, "ERROR Building upgrade row ownership changed\n"); goto finish_upgrade;
    }
    if (!building_upgrade_exec_slot) {
        HMODULE pinned;
        /* UFunction keeps a native entry pointer beyond Lua's module lifetime. */
        if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                (LPCWSTR)(uintptr_t)building_upgrade_exec, &pinned)) {
            fprintf(out, "ERROR Could not retain native building upgrade adapter\n"); goto finish_upgrade;
        }
    }
    active_upgrade = NULL;
    for (unsigned int i = 0; i < 256; i++) {
        BuildingUpgrade *entry = &upgrade_bindings[i];
        if (entry->source == source && entry->action == action) {
            if (entry->target != target || entry->source_row != (void *)(uintptr_t)source_row ||
                    entry->target_row != (void *)(uintptr_t)target_row || entry->action_row != (void *)(uintptr_t)action_row ||
                    entry->source_label != source_label || entry->target_label != target_label) {
                fprintf(out, "ERROR Upgrade ownership collision\n"); goto finish_upgrade;
            }
            active_upgrade = entry; break;
        }
    }
    if (!active_upgrade) {
        for (unsigned int i = 0; i < 256; i++) {
            if (!upgrade_bindings[i].source) { active_upgrade = &upgrade_bindings[i]; break; }
        }
    }
    if (!active_upgrade) { fprintf(out, "ERROR Upgrade registry full\n"); goto finish_upgrade; }
    snapshot = *active_upgrade; binding_changed = 1;
    building_upgrade_source = source;
    building_upgrade_target = target;
    building_upgrade_action = action;
    building_upgrade_source_row = (unsigned char *)(uintptr_t)source_row;
    building_upgrade_target_row = (unsigned char *)(uintptr_t)target_row;
    building_upgrade_action_row = (unsigned char *)(uintptr_t)action_row;
    building_upgrade_source_label = source_label;
    building_upgrade_target_label = target_label;
    if (!building_upgrade_exec_slot) {
        DWORD old_protect;
        if (!VirtualProtect(slot, sizeof(*slot), PAGE_READWRITE, &old_protect)) {
            fprintf(out, "ERROR BeginUpgrade entry is unavailable\n"); goto finish_upgrade;
        }
        building_upgrade_original = (BuildingUpgradeExec)*slot;
        *slot = (void *)building_upgrade_exec;
        DWORD unused;
        VirtualProtect(slot, sizeof(*slot), old_protect, &unused);
        building_upgrade_exec_slot = slot;
    }
    binding_success = 1;
    fprintf(out, "OK %llu %d\n", nonce, snapshot.source ? 0 : 1);
finish_upgrade:
    if (binding_changed && !binding_success) *active_upgrade = snapshot;
    if (in) fclose(in);
    fclose(out);
    return 0;
}
#endif
