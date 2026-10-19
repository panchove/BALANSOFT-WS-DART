/* sglb-ui.js — UI auxiliar del panel administrativo (mismo tema que el LM).
 *
 * Componentes globales consistentes con el tema (ver css/balansoft.css):
 *   - showToast(message, type)          -> notificación flotante (success/error/danger/warning/info)
 *   - SGLB.confirm(opts) -> Promise     -> modal de confirmación estilizado
 *   - SGLB.confirmSubmit(event, msg)    -> wrapper para forms clásicos
 */
(function () {
    'use strict';

    if (window.SGLB) return; // ya inicializado

    var TYPE_MAP = {
        success: 'success',
        error: 'danger',
        danger: 'danger',
        warning: 'warning',
        info: 'info',
    };

    var ICONS = {
        success: 'bi-check-circle-fill',
        danger: 'bi-x-octagon-fill',
        warning: 'bi-exclamation-triangle-fill',
        info: 'bi-info-circle-fill',
    };

    function escapeHtml(value) {
        var d = document.createElement('div');
        d.textContent = String(value);
        return d.innerHTML;
    }

    /* ============================================================
       TOASTS
       ============================================================ */
    function toastContainer() {
        var el = document.getElementById('sglbToastContainer');
        if (!el) {
            el = document.createElement('div');
            el.id = 'sglbToastContainer';
            el.className = 'sglb-toast-container';
            document.body.appendChild(el);
        }
        return el;
    }

    function dismissToast(toast, timer) {
        if (timer) clearTimeout(timer);
        toast.classList.remove('sglb-toast-visible');
        setTimeout(function () {
            if (toast.parentNode) toast.parentNode.removeChild(toast);
        }, 300);
    }

    function showToast(message, type) {
        if (message === null || message === undefined || message === '') {
            message = 'Operación realizada';
        }
        type = TYPE_MAP[type] || 'info';

        var container = toastContainer();
        var toast = document.createElement('div');
        toast.className = 'sglb-toast sglb-toast-' + type;
        toast.setAttribute('role', 'status');
        toast.setAttribute('aria-live', 'polite');
        toast.innerHTML =
            '<span class="sglb-toast-icon"><i class="bi ' + ICONS[type] + '"></i></span>' +
            '<span class="sglb-toast-body">' + escapeHtml(message) + '</span>' +
            '<button type="button" class="sglb-toast-close" aria-label="Cerrar">&times;</button>';

        container.appendChild(toast);

        var timer = setTimeout(function () { dismissToast(toast, timer); }, 4200);

        toast.querySelector('.sglb-toast-close').addEventListener('click', function () {
            dismissToast(toast, timer);
        });

        requestAnimationFrame(function () {
            toast.classList.add('sglb-toast-visible');
        });

        return toast;
    }

    window.showToast = showToast;

    /* ============================================================
       MODAL DE CONFIRMACIÓN
       ============================================================ */
    function buildConfirmModal() {
        var modal = document.createElement('div');
        modal.className = 'modal fade sglb-confirm-modal';
        modal.id = 'sglbConfirmModal';
        modal.setAttribute('tabindex', '-1');
        modal.setAttribute('aria-labelledby', 'sglbConfirmTitle');
        modal.setAttribute('aria-hidden', 'true');
        modal.innerHTML =
            '<div class="modal-dialog modal-dialog-centered sglb-confirm-dialog">' +
            '  <div class="modal-content sglb-confirm-content">' +
            '    <div class="sglb-confirm-icon-wrap">' +
            '      <span class="sglb-confirm-icon"><i class="bi bi-question-circle-fill"></i></span>' +
            '    </div>' +
            '    <h5 class="sglb-confirm-title" id="sglbConfirmTitle">Confirmar acción</h5>' +
            '    <p class="sglb-confirm-message"></p>' +
            '    <div class="sglb-confirm-actions">' +
            '      <button type="button" class="btn btn-light sglb-confirm-cancel">Cancelar</button>' +
            '      <button type="button" class="btn btn-primary sglb-confirm-ok">Confirmar</button>' +
            '    </div>' +
            '  </div>' +
            '</div>';
        document.body.appendChild(modal);
        return modal;
    }

    function getConfirmModal() {
        return document.getElementById('sglbConfirmModal') || buildConfirmModal();
    }

    function confirmAction(opts) {
        opts = opts || {};

        if (typeof bootstrap === 'undefined') {
            return Promise.resolve(window.confirm(opts.message || '¿Confirmar acción?'));
        }

        return new Promise(function (resolve) {
            var modalEl = getConfirmModal();
            var type = TYPE_MAP[opts.type] || 'warning';
            var iconEl = modalEl.querySelector('.sglb-confirm-icon i');
            var titleEl = modalEl.querySelector('.sglb-confirm-title');
            var msgEl = modalEl.querySelector('.sglb-confirm-message');
            var okBtn = modalEl.querySelector('.sglb-confirm-ok');
            var cancelBtn = modalEl.querySelector('.sglb-confirm-cancel');

            modalEl.className = 'modal fade sglb-confirm-modal sglb-confirm-' + type;
            iconEl.className = 'bi ' + (ICONS[type] || ICONS.warning);
            titleEl.textContent = opts.title || (type === 'danger' ? '¿Estás seguro?' : 'Confirmar acción');
            msgEl.textContent = opts.message || '';
            cancelBtn.textContent = opts.cancelText || 'Cancelar';
            okBtn.textContent = opts.confirmText || (type === 'danger' ? 'Eliminar' : 'Confirmar');
            okBtn.className = 'btn sglb-confirm-ok ' +
                (opts.confirmClass || (type === 'danger' ? 'btn-danger' : 'btn-primary'));

            var bsModal = bootstrap.Modal.getOrCreateInstance(modalEl, {
                backdrop: 'static',
                keyboard: false,
            });

            var settled = false;
            function finish(result) {
                if (settled) return;
                settled = true;
                bsModal.hide();
                okBtn.onclick = null;
                cancelBtn.onclick = null;
                document.removeEventListener('keydown', onKey);
                resolve(result);
            }
            function onKey(e) {
                if (e.key === 'Escape') {
                    e.preventDefault();
                    finish(false);
                }
                if (e.key === 'Enter' && e.target.tagName !== 'TEXTAREA') {
                    e.preventDefault();
                    finish(true);
                }
            }

            okBtn.onclick = function () { finish(true); };
            cancelBtn.onclick = function () { finish(false); };
            document.addEventListener('keydown', onKey);
            bsModal.show();
        });
    }

    window.SGLB = window.SGLB || {};
    SGLB.confirm = confirmAction;
    SGLB.toast = showToast;

    SGLB.confirmSubmit = function (event, message, opts) {
        event.preventDefault();
        var form = event.currentTarget;
        var options = opts || {};
        if (options.type === undefined) options.type = 'danger';
        if (options.confirmText === undefined) options.confirmText = 'Eliminar';
        confirmAction(Object.assign({ message: message }, options)).then(function (ok) {
            if (ok) form.submit();
        });
    };
})();