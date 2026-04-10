/* ═══════════════════════════════════════════════════════════
   app.js – Vue 3 Application for Webcom Elevators NUI
   ═══════════════════════════════════════════════════════════ */

const { createApp, ref, reactive, computed, onMounted, watch, nextTick } = Vue;

const app = createApp({
    setup() {
        // ─── State ──────────────────────────────────────
        const visible = ref(false);
        const currentView = ref('elevator'); // 'elevator' | 'pin' | 'password' | 'admin'

        // Elevator view
        const elevator = reactive({});
        const currentFloor = ref(null);
        const errorMessage = ref('');

        // Up/Down navigation
        const upDownIndex = ref(0);

        // PIN entry
        const pinInput = ref('');
        const pinError = ref('');
        const pinLoading = ref(false);
        const pendingFloor = ref(null); // floor waiting for PIN/password

        // Password entry
        const passwordInput = ref('');
        const passwordError = ref('');
        const passwordLoading = ref(false);

        // Admin
        const adminTab = ref('overview');
        const adminData = reactive({ groups: [], elevators: [] });
        const editorElevator = ref(null);

        // Group management
        const newGroup = reactive({ name: '', label: '', description: '', color: '#3B82F6' });
        const showGroupEditModal = ref(false);
        const editingGroup = reactive({ id: null, label: '', description: '', color: '#3B82F6' });

        // Jobs & Items for protection pickers
        const availableJobs = ref([]);
        const availableItems = ref([]);
        const jobSearch = ref('');
        const itemSearch = ref('');
        const editorJobSearch = ref('');
        const editorItemSearch = ref('');

        // Creator wizard
        const creatorStep = ref(1);
        const creatorStepLabels = ['Gruppe', 'Info', 'Etagen', 'Überprüfung'];
        const creator = reactive({
            groupId: null,
            name: '',
            label: '',
            navigationMode: 'LIST',
            cooldownMs: 5000,
            floors: [],
        });
        const newFloor = reactive({
            floorNumber: 0,
            label: '',
            position: null,
            interactionPoint: null,
            protectionType: 'NONE',
            protectionValue: '',
            protectionRank: 0,
            protectionConsume: false,
        });

        // Delete
        const showDeleteModal = ref(false);
        const deleteTarget = ref(null);
        const deleteType = ref(''); // 'elevator' | 'group'

        // Toast
        const toast = reactive({ visible: false, message: '', type: 'success' });
        let toastTimer = null;

        // ─── Computed ───────────────────────────────────
        const sortedFloors = computed(() => {
            if (!elevator.floors) return [];
            return [...elevator.floors].sort((a, b) => a.floorNumber - b.floorNumber);
        });

        const selectedUpDownFloor = computed(() => {
            const floors = sortedFloors.value;
            if (floors.length === 0) return null;
            return floors[upDownIndex.value] || floors[0];
        });

        const canProceedCreator = computed(() => {
            switch (creatorStep.value) {
                case 1: return creator.groupId !== null;
                case 2: return creator.name && creator.label;
                case 3: return creator.floors.length > 0;
                default: return true;
            }
        });

        // Filtered jobs/items for searchable selects
        const filteredJobs = computed(() => {
            const q = jobSearch.value.toLowerCase();
            if (!q) return availableJobs.value;
            return availableJobs.value.filter(j =>
                j.name.toLowerCase().includes(q) || j.label.toLowerCase().includes(q)
            );
        });

        const filteredItems = computed(() => {
            const q = itemSearch.value.toLowerCase();
            if (!q) return availableItems.value;
            return availableItems.value.filter(i =>
                i.name.toLowerCase().includes(q) || i.label.toLowerCase().includes(q)
            );
        });

        const selectedJobGrades = computed(() => {
            const j = availableJobs.value.find(x => x.name === newFloor.protectionValue);
            return j ? j.grades : [];
        });

        const filteredEditorJobs = computed(() => {
            const q = editorJobSearch.value.toLowerCase();
            if (!q) return availableJobs.value;
            return availableJobs.value.filter(j =>
                j.name.toLowerCase().includes(q) || j.label.toLowerCase().includes(q)
            );
        });

        const filteredEditorItems = computed(() => {
            const q = editorItemSearch.value.toLowerCase();
            if (!q) return availableItems.value;
            return availableItems.value.filter(i =>
                i.name.toLowerCase().includes(q) || i.label.toLowerCase().includes(q)
            );
        });

        function getJobGrades(jobName) {
            const j = availableJobs.value.find(x => x.name === jobName);
            return j ? j.grades : [];
        }

        function getJobLabel(jobName) {
            const j = availableJobs.value.find(x => x.name === jobName);
            return j ? j.label : jobName;
        }

        function getItemImage(itemName) {
            const i = availableItems.value.find(x => x.name === itemName);
            return i ? i.image : (itemName + '.png');
        }

        function getItemImagePath(itemName) {
            const i = availableItems.value.find(x => x.name === itemName);
            if (!i) return '';
            if (i.imagePath) return i.imagePath;
            if (i.image) return 'https://cfx-nui-ox_inventory/web/images/' + i.image;
            return '';
        }

        // ─── NUI Message Handler ────────────────────────
        window.addEventListener('message', (event) => {
            const data = event.data;
            if (!data || !data.type) return;

            switch (data.type) {
                case 'open':
                    handleOpen(data);
                    break;
                case 'close':
                    visible.value = false;
                    break;
                case 'teleportError':
                    errorMessage.value = data.message || data.reason || 'Fehler';
                    if (data.reason === 'wrong_pin') {
                        pinError.value = data.message || 'Falsche PIN';
                        pinInput.value = '';
                    }
                    if (data.reason === 'wrong_password') {
                        passwordError.value = data.message || 'Falsches Passwort';
                    }
                    break;
                case 'adminData':
                    adminData.groups = data.data?.groups || [];
                    availableJobs.value = data.data?.jobs || [];
                    availableItems.value = data.data?.items || [];
                    // Build flat elevator list from groups
                    adminData.elevators = [];
                    for (const g of adminData.groups) {
                        if (g.elevators) {
                            for (const e of g.elevators) {
                                adminData.elevators.push({ ...e, groupLabel: g.label, groupColor: g.color });
                            }
                        }
                    }
                    break;
                case 'adminResult':
                    if (data.ok) {
                        showToast(data.message || 'Erfolgreich', 'success');
                        // Server-side Lua already triggers adminGetData refresh
                    } else {
                        showToast(data.message || 'Fehler', 'error');
                    }
                    break;
                case 'pointSelected':
                    handlePointSelected(data.context, data.point);
                    break;
                case 'hide':
                    visible.value = false;
                    break;
                case 'show':
                    visible.value = true;
                    break;
            }
        });

        // ─── Open Handler ───────────────────────────────
        function handleOpen(data) {
            errorMessage.value = '';
            pinInput.value = '';
            pinError.value = '';
            passwordInput.value = '';
            passwordError.value = '';

            if (data.view === 'elevator') {
                Object.assign(elevator, data.data.elevator || {});
                currentFloor.value = data.data.currentFloor || null;
                currentView.value = 'elevator';

                // Initialize up/down index
                if (currentFloor.value && sortedFloors.value.length > 0) {
                    const idx = sortedFloors.value.findIndex(f => f.id === currentFloor.value.id);
                    upDownIndex.value = idx >= 0 ? idx : 0;
                } else {
                    upDownIndex.value = 0;
                }
            } else if (data.view === 'admin') {
                currentView.value = 'admin';
                adminTab.value = 'overview';
                adminData.groups = data.data?.groups || [];
                availableJobs.value = data.data?.jobs || [];
                availableItems.value = data.data?.items || [];
                // Build flat elevator list from groups
                adminData.elevators = [];
                for (const g of adminData.groups) {
                    if (g.elevators) {
                        for (const e of g.elevators) {
                            adminData.elevators.push({ ...e, groupLabel: g.label, groupColor: g.color });
                        }
                    }
                }
            }

            visible.value = true;
        }

        // ─── Floor Selection ────────────────────────────
        function selectFloor(floor) {
            if (!floor) return;
            if (currentFloor.value && floor.id === currentFloor.value.id) return;

            errorMessage.value = '';

            const pType = (floor.protectionType || 'NONE').toUpperCase();

            if (pType === 'PIN') {
                pendingFloor.value = floor;
                pinInput.value = '';
                pinError.value = '';
                currentView.value = 'pin';
                return;
            }
            if (pType === 'PASSWORD') {
                pendingFloor.value = floor;
                passwordInput.value = '';
                passwordError.value = '';
                currentView.value = 'password';
                return;
            }

            // Direct teleport (NONE, JOB, ITEM — server validates)
            nuiCallback('selectFloor', {
                elevatorId: elevator.id,
                floorId: floor.id,
            });
        }

        // ─── Up/Down Navigation ─────────────────────────
        function upDownMove(direction) {
            const newIdx = upDownIndex.value + direction;
            if (newIdx >= 0 && newIdx < sortedFloors.value.length) {
                upDownIndex.value = newIdx;
            }
        }

        // ─── PIN ────────────────────────────────────────
        function pinPress(n) {
            if (pinInput.value.length < 6) {
                pinInput.value += String(n);
                pinError.value = '';
            }
        }

        function submitPin() {
            if (pinInput.value.length < 4 || !pendingFloor.value) return;
            pinLoading.value = true;
            pinError.value = '';

            nuiCallback('submitPin', {
                elevatorId: elevator.id,
                floorId: pendingFloor.value.id,
                pin: pinInput.value,
            });

            // Loading state reset after timeout
            setTimeout(() => { pinLoading.value = false; }, 3000);
        }

        // ─── Password ───────────────────────────────────
        function submitPassword() {
            if (!passwordInput.value || !pendingFloor.value) return;
            passwordLoading.value = true;
            passwordError.value = '';

            nuiCallback('submitPassword', {
                elevatorId: elevator.id,
                floorId: pendingFloor.value.id,
                password: passwordInput.value,
            });

            setTimeout(() => { passwordLoading.value = false; }, 3000);
        }

        function cancelProtection() {
            pendingFloor.value = null;
            currentView.value = 'elevator';
        }

        // ─── Protection Helpers ─────────────────────────
        function protectionIcon(type) {
            const t = (type || '').toUpperCase();
            const icons = {
                PIN: 'fas fa-hashtag',
                PASSWORD: 'fas fa-key',
                JOB: 'fas fa-briefcase',
                ITEM: 'fas fa-box',
            };
            return icons[t] || 'fas fa-lock';
        }

        function protectionLabel(type) {
            const t = (type || '').toUpperCase();
            const labels = {
                PIN: 'PIN',
                PASSWORD: 'Passwort',
                JOB: 'Job',
                ITEM: 'Item',
            };
            return labels[t] || 'Geschützt';
        }

        // ─── Admin: Group Operations ────────────────────
        function createGroup() {
            if (!newGroup.name || !newGroup.label) return;
            nuiCallback('createGroup', {
                name: newGroup.name,
                label: newGroup.label,
                description: newGroup.description,
                color: newGroup.color,
            });
            newGroup.name = '';
            newGroup.label = '';
            newGroup.description = '';
            newGroup.color = '#3B82F6';
        }

        function editGroup(group) {
            editingGroup.id = group.id;
            editingGroup.label = group.label;
            editingGroup.description = group.description || '';
            editingGroup.color = group.color || '#3B82F6';
            showGroupEditModal.value = true;
        }

        function saveGroupEdit() {
            nuiCallback('updateGroup', {
                id: editingGroup.id,
                label: editingGroup.label,
                description: editingGroup.description,
                color: editingGroup.color,
            });
            showGroupEditModal.value = false;
        }

        function confirmDeleteGroup(group) {
            deleteTarget.value = group;
            deleteType.value = 'group';
            showDeleteModal.value = true;
        }

        // ─── Admin: Elevator Operations ─────────────────
        function editElevator(elev) {
            editorElevator.value = JSON.parse(JSON.stringify(elev));
            adminTab.value = 'editor';
        }

        function toggleElevator(id) {
            nuiCallback('toggleElevator', { id });
        }

        function confirmDeleteElevator(elev) {
            deleteTarget.value = elev;
            deleteType.value = 'elevator';
            showDeleteModal.value = true;
        }

        function confirmDelete() {
            if (deleteType.value === 'elevator') {
                nuiCallback('deleteElevator', { id: deleteTarget.value.id });
            } else if (deleteType.value === 'group') {
                nuiCallback('deleteGroup', { id: deleteTarget.value.id });
            }
            showDeleteModal.value = false;
            deleteTarget.value = null;
        }

        function saveEditor() {
            if (!editorElevator.value) return;
            nuiCallback('updateElevator', {
                id: editorElevator.value.id,
                label: editorElevator.value.label,
                groupId: editorElevator.value.groupId,
                navigationMode: editorElevator.value.navigationMode,
                interactionType: editorElevator.value.interactionType,
                cooldownMs: editorElevator.value.cooldownMs,
                isActive: editorElevator.value.isActive,
            });
            editorElevator.value = null;
            adminTab.value = 'overview';
        }

        // ─── Admin: Editor Floor Operations ─────────────
        function saveEditorFloor(floor) {
            nuiCallback('updateFloor', {
                id: floor.id,
                floorNumber: floor.floorNumber,
                label: floor.label,
                position: floor.position,
                interactionPoint: floor.interactionPoint,
                protectionType: floor.protectionType,
                protectionData: buildEditorProtectionData(floor),
                isActive: floor.isActive !== false,
            });
        }

        function deleteEditorFloor(floorId) {
            nuiCallback('deleteFloor', { id: floorId });
            if (editorElevator.value && editorElevator.value.floors) {
                editorElevator.value.floors = editorElevator.value.floors.filter(f => f.id !== floorId);
            }
        }

        // Editor: inline add floor state
        const editorAddingFloor = ref(false);
        const editorNewFloor = reactive({
            floorNumber: 0,
            label: '',
            position: null,
            interactionPoint: null,
            protectionType: 'NONE',
            protectionValue: '',
            protectionRank: 0,
            protectionConsume: false,
        });

        function addFloorToEditor() {
            if (!editorElevator.value) return;
            const nums = (editorElevator.value.floors || []).map(f => f.floorNumber || 0);
            const nextNum = nums.length > 0 ? Math.max(...nums) + 1 : 0;
            editorNewFloor.floorNumber = nextNum;
            editorNewFloor.label = '';
            editorNewFloor.position = null;
            editorNewFloor.interactionPoint = null;
            editorNewFloor.protectionType = 'NONE';
            editorNewFloor.protectionValue = '';
            editorNewFloor.protectionRank = 0;
            editorNewFloor.protectionConsume = false;
            editorAddingFloor.value = true;
        }

        function submitEditorNewFloor() {
            if (!editorElevator.value || !editorNewFloor.label || !editorNewFloor.position) return;
            nuiCallback('addFloor', {
                elevatorId: editorElevator.value.id,
                floor: {
                    floorNumber: editorNewFloor.floorNumber,
                    label: editorNewFloor.label,
                    position: editorNewFloor.position,
                    interactionPoint: editorNewFloor.interactionPoint,
                    protectionType: editorNewFloor.protectionType,
                    protectionData: buildEditorNewFloorProtection(),
                },
            });
            editorAddingFloor.value = false;
        }

        function cancelEditorNewFloor() {
            editorAddingFloor.value = false;
        }

        function buildEditorNewFloorProtection() {
            const t = editorNewFloor.protectionType;
            if (t === 'NONE') return null;
            if (t === 'PIN') return { pin: editorNewFloor.protectionValue };
            if (t === 'PASSWORD') return { password: editorNewFloor.protectionValue };
            if (t === 'JOB') return { job: editorNewFloor.protectionValue, minRank: editorNewFloor.protectionRank || 0 };
            if (t === 'ITEM') return { item: editorNewFloor.protectionValue, consume: editorNewFloor.protectionConsume };
            return null;
        }

        function selectEditorFloorPoint(floor, type) {
            nuiCallback('selectPoint', { context: 'editorFloor_' + type + '_' + floor.id });
        }

        // ─── Admin: Creator ─────────────────────────────
        function resetCreator() {
            creatorStep.value = 1;
            creator.groupId = null;
            creator.name = '';
            creator.label = '';
            creator.navigationMode = 'LIST';
            creator.cooldownMs = 5000;
            creator.floors = [];
            resetNewFloor();
        }

        function resetNewFloor() {
            newFloor.floorNumber = creator.floors.length;
            newFloor.label = '';
            newFloor.position = null;
            newFloor.interactionPoint = null;
            newFloor.protectionType = 'NONE';
            newFloor.protectionValue = '';
            newFloor.protectionRank = 0;
            newFloor.protectionConsume = false;
        }

        function addCreatorFloor() {
            if (!newFloor.label || !newFloor.position) return;

            creator.floors.push({
                floorNumber: newFloor.floorNumber,
                label: newFloor.label,
                position: { ...newFloor.position },
                interactionPoint: newFloor.interactionPoint ? { ...newFloor.interactionPoint } : null,
                protectionType: newFloor.protectionType,
                protectionData: buildNewFloorProtectionData(),
            });

            resetNewFloor();
        }

        function buildNewFloorProtectionData() {
            const t = newFloor.protectionType;
            if (t === 'NONE') return null;
            if (t === 'PIN') return { pin: newFloor.protectionValue };
            if (t === 'PASSWORD') return { password: newFloor.protectionValue };
            if (t === 'JOB') return { job: newFloor.protectionValue, minRank: newFloor.protectionRank || 0 };
            if (t === 'ITEM') return { item: newFloor.protectionValue, consume: newFloor.protectionConsume };
            return null;
        }

        function buildProtectionData(floor) {
            // Used for editor floor save
            const t = (floor.protectionType || 'NONE').toUpperCase();
            if (t === 'NONE') return null;
            // Keep existing data if available
            return floor.protectionData || null;
        }

        function buildEditorProtectionData(floor) {
            const t = (floor.protectionType || 'NONE').toUpperCase();
            if (t === 'NONE') return null;
            if (t === 'PIN') return { pin: floor.protectionData?.pin || '' };
            if (t === 'PASSWORD') return { password: floor.protectionData?.password || '' };
            if (t === 'JOB') return { job: floor.protectionData?.job || '', minRank: floor.protectionData?.minRank || 0 };
            if (t === 'ITEM') return { item: floor.protectionData?.item || '', consume: floor.protectionData?.consume || false };
            return floor.protectionData || null;
        }

        function submitCreator() {
            nuiCallback('createElevator', {
                groupId: creator.groupId,
                name: creator.name,
                label: creator.label,
                navigationMode: creator.navigationMode,
                cooldownMs: creator.cooldownMs,
                floors: creator.floors,
            });
            resetCreator();
            adminTab.value = 'overview';
        }

        function getGroupLabel(id) {
            const g = adminData.groups.find(g => g.id === id);
            return g ? g.label : 'Unbekannt';
        }

        // ─── Point Selection ────────────────────────────
        function selectPoint(context) {
            nuiCallback('selectPoint', { context });
        }

        function handlePointSelected(context, point) {
            if (!point) return;

            if (context === 'floorPosition') {
                newFloor.position = point;
            } else if (context === 'floorInteraction') {
                newFloor.interactionPoint = point;
            } else if (context === 'editorNewFloorPosition') {
                editorNewFloor.position = point;
            } else if (context === 'editorNewFloorInteraction') {
                editorNewFloor.interactionPoint = point;
            } else if (context && context.startsWith('editorFloor_')) {
                // editorFloor_position_123 or editorFloor_interaction_123
                const parts = context.split('_');
                const type = parts[1];
                const floorId = parseInt(parts[2]);
                if (editorElevator.value && editorElevator.value.floors) {
                    const floor = editorElevator.value.floors.find(f => f.id === floorId);
                    if (floor) {
                        if (type === 'position') floor.position = point;
                        else if (type === 'interaction') floor.interactionPoint = point;
                    }
                }
            }

            // Re-show the UI
            visible.value = true;
        }

        // ─── NUI Callback ───────────────────────────────
        function nuiCallback(name, data) {
            fetch(`https://webcom_elevators/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data || {}),
            }).catch(() => {});
        }

        // ─── Close ──────────────────────────────────────
        function close() {
            visible.value = false;
            nuiCallback('close', {});
        }

        // ─── Toast ──────────────────────────────────────
        function showToast(msg, type) {
            toast.message = msg;
            toast.type = type || 'success';
            toast.visible = true;
            if (toastTimer) clearTimeout(toastTimer);
            toastTimer = setTimeout(() => { toast.visible = false; }, 3000);
        }

        // ─── Keyboard handler ───────────────────────────
        window.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && visible.value) {
                if (currentView.value === 'pin' || currentView.value === 'password') {
                    cancelProtection();
                } else {
                    close();
                }
            }
        });

        return {
            visible,
            currentView,
            elevator,
            currentFloor,
            errorMessage,
            sortedFloors,
            upDownIndex,
            selectedUpDownFloor,
            pinInput,
            pinError,
            pinLoading,
            passwordInput,
            passwordError,
            passwordLoading,
            adminTab,
            adminData,
            editorElevator,
            newGroup,
            showGroupEditModal,
            editingGroup,
            creatorStep,
            creatorStepLabels,
            creator,
            newFloor,
            canProceedCreator,
            availableJobs,
            availableItems,
            jobSearch,
            itemSearch,
            editorJobSearch,
            editorItemSearch,
            filteredJobs,
            filteredItems,
            selectedJobGrades,
            filteredEditorJobs,
            filteredEditorItems,
            getJobGrades,
            getJobLabel,
            getItemImage,
            getItemImagePath,
            showDeleteModal,
            deleteTarget,
            toast,
            selectFloor,
            upDownMove,
            pinPress,
            submitPin,
            submitPassword,
            cancelProtection,
            protectionIcon,
            protectionLabel,
            createGroup,
            editGroup,
            saveGroupEdit,
            confirmDeleteGroup,
            editElevator,
            toggleElevator,
            confirmDeleteElevator,
            confirmDelete,
            saveEditor,
            saveEditorFloor,
            deleteEditorFloor,
            addFloorToEditor,
            selectEditorFloorPoint,
            editorAddingFloor,
            editorNewFloor,
            submitEditorNewFloor,
            cancelEditorNewFloor,
            resetCreator,
            addCreatorFloor,
            submitCreator,
            getGroupLabel,
            selectPoint,
            close,
        };
    },
});

app.mount('#app');
