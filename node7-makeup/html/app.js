(() => {
    const app = document.getElementById('app');
    const shopName = document.getElementById('shopName');
    const tabs = document.getElementById('tabs');
    const content = document.getElementById('content');
    const feedback = document.getElementById('feedback');
    const price = document.getElementById('price');
    const cashBalance = document.getElementById('cashBalance');
    const bankBalance = document.getElementById('bankBalance');
    const closeButton = document.getElementById('closeButton');

    const state = {
        open: false,
        purchasing: false,
        activeTab: 'eyes',
        profile: null,
        catalog: { gender: 'male', eyeColors: 14, beard: { models: 0, textures: [], styles: [] }, overlays: [], featureGroups: [] },
        money: {},
        payments: { cash: true, bank: true },
        price: 0,
        busy: new Set(),
        featureTimers: new Map()
    };

    function isMaleSession() {
        return state.catalog.gender === 'male' || state.catalog.isMale === true;
    }

    function tabDefinitions() {
        if (isMaleSession()) {
            return [
                { id: 'eyes', label: 'Eyes' },
                { id: 'beard', label: 'Beard' },
                { id: 'details', label: 'Details' },
                { id: 'face', label: 'Sculpt' }
            ];
        }
        return [
            { id: 'eyes', label: 'Eyes' },
            { id: 'makeup', label: 'Makeup' },
            { id: 'details', label: 'Details' },
            { id: 'face', label: 'Sculpt' }
        ];
    }

    const resourceName = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'node7-makeup';

    async function nui(name, payload = {}) {
        const response = await fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload)
        });
        return response.json();
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function money(value) {
        return `$${Math.max(0, Number(value) || 0).toLocaleString('en-CA')}`;
    }

    function wrap(value, minimum, maximum) {
        if (maximum < minimum) return minimum;
        if (value > maximum) return minimum;
        if (value < minimum) return maximum;
        return value;
    }

    function setFeedback(message = '', type = '') {
        feedback.textContent = message;
        feedback.className = `feedback${type ? ` ${type}` : ''}`;
    }

    function setDisabled(disabled) {
        document.querySelectorAll('button, input').forEach((element) => {
            if (element === closeButton) {
                element.disabled = false;
                return;
            }
            if (element.dataset.paymentMethod) {
                element.disabled = disabled || !state.payments[element.dataset.paymentMethod];
                return;
            }
            element.disabled = disabled;
        });
    }

    function overlayCatalog(key) {
        return state.catalog.overlays.find((entry) => entry.key === key);
    }

    function overlaySelection(key) {
        if (!state.profile.overlays[key]) {
            state.profile.overlays[key] = {
                style: 0, palette: 1, color1: 0, color2: 0, color3: 0, variant: 0, opacity: 100
            };
        }
        return state.profile.overlays[key];
    }

    async function previewOverlay(key, nextSelection) {
        if (!state.open || state.purchasing || state.busy.has(key)) return false;
        state.busy.add(key);
        setFeedback('Applying makeup preview...');
        renderContent();

        try {
            const result = await nui('previewOverlay', { overlay: key, selection: nextSelection });
            if (!result.success) {
                setFeedback(result.message || 'The makeup layer could not be applied.', 'error');
                return false;
            }
            state.profile.overlays[key] = result.selection || nextSelection;
            state.profile.ownsOverlays = true;
            setFeedback('Preview applied.', 'success');
            return true;
        } catch (_) {
            setFeedback('The game client did not accept the makeup preview.', 'error');
            return false;
        } finally {
            state.busy.delete(key);
            renderContent();
        }
    }

    function createStepper(label, valueText, onPrevious, onNext, disabled = false) {
        const row = document.createElement('div');
        row.className = 'control-row';

        const labelElement = document.createElement('span');
        labelElement.className = 'control-label';
        labelElement.textContent = label;

        const stepper = document.createElement('div');
        stepper.className = 'stepper';

        const previous = document.createElement('button');
        previous.type = 'button';
        previous.className = 'step-button';
        previous.textContent = '‹';
        previous.disabled = disabled;
        previous.addEventListener('click', onPrevious);

        const value = document.createElement('strong');
        value.className = 'step-value';
        value.textContent = valueText;

        const next = document.createElement('button');
        next.type = 'button';
        next.className = 'step-button';
        next.textContent = '›';
        next.disabled = disabled;
        next.addEventListener('click', onNext);

        stepper.append(previous, value, next);
        row.append(labelElement, stepper);
        return row;
    }

    function createRange(label, current, minimum, maximum, onInput) {
        const row = document.createElement('div');
        row.className = 'control-row';

        const labelElement = document.createElement('span');
        labelElement.className = 'control-label';
        labelElement.textContent = label;

        const wrapElement = document.createElement('div');
        wrapElement.className = 'range-wrap';

        const input = document.createElement('input');
        input.type = 'range';
        input.min = String(minimum);
        input.max = String(maximum);
        input.step = '1';
        input.value = String(current);

        const output = document.createElement('span');
        output.className = 'range-value';
        output.textContent = String(current);

        input.addEventListener('input', () => {
            output.textContent = input.value;
            onInput(Number(input.value));
        });

        wrapElement.append(input, output);
        row.append(labelElement, wrapElement);
        return row;
    }

    function createOverlayCard(entry) {
        const selection = overlaySelection(entry.key);
        const card = document.createElement('article');
        card.className = 'control-card';

        const heading = document.createElement('h3');
        heading.textContent = entry.label;
        card.append(heading);

        const busy = state.busy.has(entry.key) || state.purchasing;
        const styleText = selection.style === 0 ? 'None' : `${selection.style} / ${entry.styles}`;
        card.append(createStepper(
            'Style',
            styleText,
            async () => {
                const next = clone(selection);
                next.style = wrap(Number(next.style) - 1, 0, entry.styles);
                if (next.style > 0 && next.opacity === 0) next.opacity = 100;
                await previewOverlay(entry.key, next);
            },
            async () => {
                const next = clone(selection);
                next.style = wrap(Number(next.style) + 1, 0, entry.styles);
                if (next.style > 0 && next.opacity === 0) next.opacity = 100;
                await previewOverlay(entry.key, next);
            },
            busy
        ));

        if (entry.maxVariant > 0 && selection.style > 0) {
            card.append(createStepper(
                'Variant',
                `${selection.variant} / ${entry.maxVariant}`,
                async () => {
                    const next = clone(selection);
                    next.variant = wrap(Number(next.variant) - 1, 0, entry.maxVariant);
                    await previewOverlay(entry.key, next);
                },
                async () => {
                    const next = clone(selection);
                    next.variant = wrap(Number(next.variant) + 1, 0, entry.maxVariant);
                    await previewOverlay(entry.key, next);
                },
                busy
            ));
        }

        if (entry.tint && selection.style > 0) {

            card.append(createRange('Color', selection.color1, 0, 63, (value) => {
                const next = clone(selection);
                next.color1 = value;
                next.color2 = 0;
                next.color3 = 0;
                clearTimeout(card.colorTimer);
                card.colorTimer = setTimeout(() => previewOverlay(entry.key, next), 180);
            }));
        }

        if (selection.style > 0) {
            card.append(createRange('Opacity', selection.opacity, 0, 100, (value) => {
                const next = clone(selection);
                next.opacity = value;
                clearTimeout(card.opacityTimer);
                card.opacityTimer = setTimeout(() => previewOverlay(entry.key, next), 180);
            }));
        }

        return card;
    }

    function beardSelection() {
        if (!state.profile.beard) {
            state.profile.beard = { model: 0, texture: 1, hash: 0, remove: true };
        }
        return state.profile.beard;
    }

    function beardStyles() {
        const styles = state.catalog.beard && state.catalog.beard.styles;
        return Array.isArray(styles) ? styles : [];
    }

    function beardStyle(model) {
        return beardStyles().find((entry) => Number(entry.model) === Number(model));
    }

    function beardTextureCount(model) {
        const entry = beardStyle(model);
        return entry && Array.isArray(entry.colors) ? Math.max(1, entry.colors.length) : 1;
    }

    function beardStyleLabel(model) {
        const entry = beardStyle(model);
        return entry && entry.label ? entry.label : `Native Beard ${String(model).padStart(2, '0')}`;
    }

    function beardColorLabel(model, texture) {
        const entry = beardStyle(model);
        const colors = entry && Array.isArray(entry.colors) ? entry.colors : [];
        const color = colors.find((item) => Number(item.texture) === Number(texture));
        return color && color.label ? color.label : `Color ${texture}`;
    }

    function nextBeardModel(current, direction) {
        const models = beardStyles().map((entry) => Number(entry.model)).filter((value) => value > 0);
        if (!models.length) return 0;
        if (Number(current) === 0) return direction > 0 ? models[0] : models[models.length - 1];
        const index = models.indexOf(Number(current));
        if (index < 0) return models[0];
        const nextIndex = (index + direction + models.length) % models.length;
        return models[nextIndex];
    }

    async function previewBeard(nextSelection) {
        if (!state.open || state.purchasing || state.busy.has('beard')) return false;
        state.busy.add('beard');
        setFeedback('Applying beard preview...');
        renderContent();

        try {
            const result = await nui('previewBeard', { selection: nextSelection });
            if (!result.success) {
                setFeedback(result.message || 'The beard could not be applied.', 'error');
                return false;
            }
            state.profile.beard = result.selection || nextSelection;
            state.profile.ownsBeard = result.ownsBeard === true;
            setFeedback('Beard preview applied.', 'success');
            return true;
        } catch (_) {
            setFeedback('The game client did not accept the beard preview.', 'error');
            return false;
        } finally {
            state.busy.delete('beard');
            renderContent();
        }
    }

    function createBeardCard() {
        const selection = beardSelection();
        const styles = beardStyles();
        const model = Math.max(0, Number(selection.model) || 0);
        const textureMax = model > 0 ? beardTextureCount(model) : 1;
        const texture = Math.min(textureMax, Math.max(1, Number(selection.texture) || 1));

        const card = document.createElement('article');
        card.className = 'control-card';
        const heading = document.createElement('h3');
        heading.textContent = 'Facial Hair';
        card.append(heading);

        const busy = state.busy.has('beard') || state.purchasing;
        if (!styles.length) {
            const warning = document.createElement('p');
            warning.className = 'section-copy';
            warning.textContent = 'Native beard catalog failed to load.';
            card.append(warning);
            return card;
        }
        card.append(createStepper(
            'Style',
            model === 0 ? 'None' : beardStyleLabel(model),
            async () => {
                const nextModel = nextBeardModel(model, -1);
                await previewBeard({ model: nextModel, texture: 1, remove: nextModel === 0 });
            },
            async () => {
                const nextModel = nextBeardModel(model, 1);
                await previewBeard({ model: nextModel, texture: 1, remove: nextModel === 0 });
            },
            busy
        ));

        if (model > 0) {
            card.append(createStepper(
                'Color',
                beardColorLabel(model, texture),
                async () => previewBeard({ model, texture: wrap(texture - 1, 1, textureMax), remove: false }),
                async () => previewBeard({ model, texture: wrap(texture + 1, 1, textureMax), remove: false }),
                busy
            ));
        }

        return card;
    }

    function createEyeColorCard() {
        const card = document.createElement('article');
        card.className = 'control-card';
        const heading = document.createElement('h3');
        heading.textContent = 'Eye Color';
        card.append(heading);

        const value = Number(state.profile.eyeColor) || 0;
        card.append(createStepper(
            'Native Color',
            value === 0 ? 'Current' : `${value} / ${state.catalog.eyeColors}`,
            () => previewEye(wrap(value - 1, 0, state.catalog.eyeColors)),
            () => previewEye(wrap(value + 1, 0, state.catalog.eyeColors)),
            state.busy.has('eye') || state.purchasing
        ));
        return card;
    }

    async function previewEye(value) {
        if (!state.open || state.purchasing || state.busy.has('eye')) return;
        state.busy.add('eye');
        renderContent();
        try {
            const result = await nui('previewEye', { value });
            if (!result.success) {
                setFeedback(result.message || 'The eye color could not be applied.', 'error');
                return;
            }
            state.profile.eyeColor = result.value;
            setFeedback('Eye color preview applied.', 'success');
        } catch (_) {
            setFeedback('The game client did not accept the eye color.', 'error');
        } finally {
            state.busy.delete('eye');
            renderContent();
        }
    }

    function queueFeature(feature, value) {
        state.profile.features[feature] = value;
        const existing = state.featureTimers.get(feature);
        if (existing) clearTimeout(existing);
        const timer = setTimeout(async () => {
            state.featureTimers.delete(feature);
            try {
                const result = await nui('previewFeature', { feature, value: state.profile.features[feature] });
                if (!result.success) setFeedback(result.message || 'The facial adjustment could not be applied.', 'error');
            } catch (_) {
                setFeedback('The game client did not accept the facial adjustment.', 'error');
            }
        }, 160);
        state.featureTimers.set(feature, timer);
    }

    function renderFeatureGroups() {
        const fragment = document.createDocumentFragment();
        state.catalog.featureGroups.forEach((group) => {
            const section = document.createElement('section');
            section.className = 'control-card feature-group';
            const heading = document.createElement('h3');
            heading.className = 'feature-group-title';
            heading.textContent = group.label;
            section.append(heading);

            group.features.forEach((feature) => {
                const current = Number(state.profile.features[feature.key]) || 0;
                section.append(createRange(feature.label, current, feature.min, feature.max, (value) => {
                    queueFeature(feature.key, value);
                }));
            });
            fragment.append(section);
        });
        return fragment;
    }

    function renderTabs() {
        tabs.replaceChildren();
        tabDefinitions().forEach((tab) => {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = `tab-button${state.activeTab === tab.id ? ' active' : ''}`;
            button.textContent = tab.label;
            button.addEventListener('click', () => {
                state.activeTab = tab.id;
                renderTabs();
                renderContent();
            });
            tabs.append(button);
        });
    }

    function renderContent() {
        content.replaceChildren();
        if (!state.profile) return;

        const title = document.createElement('h2');
        title.className = 'section-title';
        const copy = document.createElement('p');
        copy.className = 'section-copy';

        if (state.activeTab === 'eyes') {
            title.textContent = 'Eyes & Brows';
            copy.textContent = 'Native eye colors and eyebrow layers.';
            content.append(title, copy, createEyeColorCard());
            state.catalog.overlays.filter((entry) => entry.group === 'eyes').forEach((entry) => {
                content.append(createOverlayCard(entry));
            });
        } else if (state.activeTab === 'beard') {
            title.textContent = 'Beard';
            copy.textContent = 'Male native beard styles and colors.';
            content.append(title, copy, createBeardCard());
        } else if (state.activeTab === 'makeup') {
            title.textContent = 'Makeup';
            copy.textContent = 'Layered cosmetics are rebuilt together so one option does not erase another.';
            content.append(title, copy);
            state.catalog.overlays.filter((entry) => entry.group === 'makeup').forEach((entry) => {
                content.append(createOverlayCard(entry));
            });
        } else if (state.activeTab === 'details') {
            title.textContent = 'Face Details';
            copy.textContent = 'Adds native face-detail overlays without changing the character skin tone or head.';
            content.append(title, copy);
            state.catalog.overlays.filter((entry) => entry.group === 'details').forEach((entry) => {
                content.append(createOverlayCard(entry));
            });
        } else {
            title.textContent = 'Face Sculpt';
            copy.textContent = 'Adjust native MetaPed facial morphs. Only touched values are stored.';
            content.append(title, copy, renderFeatureGroups());
        }

        setDisabled(state.purchasing);
    }

    async function purchase(method) {
        if (!state.open || state.purchasing || !state.payments[method]) return;
        state.purchasing = true;
        setDisabled(true);
        setFeedback(`Processing ${method} payment...`);

        try {
            const result = await nui('purchase', { method });
            if (!result.success) {
                state.purchasing = false;
                setDisabled(false);
                setFeedback(result.message || 'The purchase could not start.', 'error');
            }
        } catch (_) {
            state.purchasing = false;
            setDisabled(false);
            setFeedback('The game client did not accept the purchase.', 'error');
        }
    }

    async function close() {
        if (!state.open) return;
        state.open = false;
        app.classList.remove('open');
        app.setAttribute('aria-hidden', 'true');
        try { await nui('close'); } catch (_) {}
    }

    closeButton.addEventListener('click', close);
    document.querySelectorAll('[data-payment-method]').forEach((button) => {
        button.addEventListener('click', () => purchase(button.dataset.paymentMethod));
    });

    window.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') close();
    });

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.action === 'open') {
            state.open = true;
            state.purchasing = false;
            state.profile = clone(data.profile || {});
            state.catalog = clone(data.catalog || state.catalog);
            if (data.isMale === true) state.catalog.isMale = true;
            state.activeTab = isMaleSession() ? 'beard' : 'eyes';
            if (!state.profile.beard) state.profile.beard = { model: 0, texture: 1, hash: 0, remove: true };
            if (state.profile.ownsBeard !== true) state.profile.ownsBeard = false;
            state.money = clone(data.money || {});
            state.payments = clone(data.payments || { cash: true, bank: true });
            state.price = Number(data.price) || 0;
            state.busy.clear();
            state.featureTimers.forEach(clearTimeout);
            state.featureTimers.clear();

            shopName.textContent = `${data.shop || 'Barber'} barber chair`;
            price.textContent = money(state.price);
            cashBalance.textContent = `${money(state.money.cash)} available`;
            bankBalance.textContent = `${money(state.money.bank)} available`;
            setFeedback('Preview changes on the chair model, then choose a payment method.');
            renderTabs();
            renderContent();
            app.classList.add('open');
            app.setAttribute('aria-hidden', 'false');
            return;
        }

        if (data.action === 'purchaseResult') {
            if (!data.success) {
                state.purchasing = false;
                setDisabled(false);
                setFeedback(data.message || 'Payment failed.', 'error');
                return;
            }
            setFeedback('Profile saved.', 'success');
            return;
        }

        if (data.action === 'close') {
            state.open = false;
            app.classList.remove('open');
            app.setAttribute('aria-hidden', 'true');
        }
    });
})();
