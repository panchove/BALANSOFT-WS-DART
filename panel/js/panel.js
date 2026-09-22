/* Lógica del panel administrativo (panel.html). CRUD único de cuentas.
   Plan/tipo/límites de licencia vienen del License Manager (LM). */
(function () {
  window.BalansoftAuth.requireSession();
  renderSession();

  var btnLogout = document.getElementById('btnLogout');
  if (btnLogout) {
    btnLogout.addEventListener('click', function (e) {
      e.preventDefault();
      window.BalansoftAuth.logout();
    });
  }
  var btnLogoutSidebar = document.getElementById('btnLogoutSidebar');
  if (btnLogoutSidebar) {
    btnLogoutSidebar.addEventListener('click', function () {
      window.BalansoftAuth.logout();
    });
  }

  var btnTogglePassword = document.getElementById('btnTogglePassword');
  if (btnTogglePassword) {
    btnTogglePassword.addEventListener('click', function () {
      var inp = document.getElementById('ePassword');
      var show = inp.type === 'password';
      inp.type = show ? 'text' : 'password';
      btnTogglePassword.querySelector('i').className = show ? 'bi bi-eye-slash' : 'bi bi-eye';
    });
  }

  function renderSession() {
    var user = window.BalansoftAuth.sessionUser();
    var nombre = user && user.nombre ? user.nombre : 'Administrador';
    var rol = user && user.rol ? user.rol : 'Administrador';

    var el = document.getElementById('sessionUser');
    if (el) el.textContent = nombre;
    var sb = document.getElementById('sidebarUser');
    if (sb) sb.textContent = nombre;

    var badge = document.getElementById('sessionRoleBadge');
    if (badge) badge.innerHTML = '<i class="bi bi-shield-fill-check me-1"></i>' + rol;
    var badgeSidebar = document.querySelector('.sidebar-role .role-badge');
    if (badgeSidebar) badgeSidebar.textContent = rol;
  }

  function apiErrorBox(el, err) {
    el.textContent = err.message;
    el.classList.remove('d-none');
  }

  function clearBox(el) {
    el.classList.add('d-none');
    el.textContent = '';
  }

  function esc(value) {
    var div = document.createElement('div');
    div.textContent = value == null ? '' : String(value);
    return div.innerHTML;
  }

  function setText(id, value) {
    var el = document.getElementById(id);
    if (el) el.textContent = value == null ? '—' : value;
  }

  /* ---------- Utilidades del modal registrar/editar ---------- */
  var cuentaModalEl = document.getElementById('cuentaModal');
  var cuentaForm = document.getElementById('cuentaForm');
  var modalAlert = document.getElementById('modalAlert');
  var MODO = { CREAR: 'crear', EDITAR: 'editar' };
  var modo = MODO.CREAR;

  var lmData = null; // datos de la licencia obtenidos del LM
  var editKeyOriginal = ''; // clave original al abrir el modal en edición

  function setRequired(id, req) {
    var el = document.getElementById(id);
    if (el) el.required = !!req;
  }

  function showModalMsg(kind, message) {
    modalAlert.className =
      'alert alert-box alert-' +
      (kind === 'danger' ? 'danger' : kind === 'warning' ? 'warning' : kind === 'info' ? 'info' : 'success') +
      ' mt-0';
    modalAlert.innerHTML = message;
    if (modalAlert.classList.contains('d-none')) modalAlert.classList.remove('d-none');
  }

  function hideModalMsg() {
    modalAlert.className = 'alert alert-box d-none';
    modalAlert.innerHTML = '';
  }

  function spinnerOn(on) {
    var btn = document.getElementById('btnGuardarCuenta');
    var spinner = document.getElementById('spinnerGuardar');
    btn.disabled = on;
    spinner.classList.toggle('d-none', !on);
  }

  function planTypeLabel(pt) {
    if (!pt) return '—';
    var t = String(pt).toUpperCase();
    if (t === 'BASIC') return 'Básica';
    if (t === 'PREMIUM' || t === 'ADVANCED') return 'Avanzada';
    return pt;
  }

  function lmMaxEquipos(verify) {
    var f = verify && verify.features;
    if (f && f.max_activations != null) return Number(f.max_activations);
    return String(verify && verify.tier || '').toUpperCase() === 'CENTRAL' ? 3 : 1;
  }

  function lmMaxUsuarios(verify) {
    var f = verify && verify.features;
    if (f && f.max_users != null) return Number(f.max_users);
    return String(verify && verify.tier || '').toUpperCase() === 'CENTRAL' ? 10 : 1;
  }

  function fillLmBlock(data) {
    var has = data && data.tier;
    setText('lmTier', has ? data.tier : '—');
    setText('lmPlanType', has ? planTypeLabel(data.plan_type) : '—');
    setText('lmExpira', has ? (data.expires_at ? window.BalansoftHelpers.fmtFecha(data.expires_at) : '—') : '—');
    setText('lmMaxEquipos', has ? (data.max_equipos != null ? data.max_equipos : '—') : '—');
    setText('lmMaxUsuarios', has ? (data.max_usuarios != null ? data.max_usuarios : '—') : '—');
    setText('lmCliente', has ? (data.client_name || '—') : '—');
    setText('lmDistribuidor', has ? (data.distributor_name || '—') : '—');
    var nota = document.getElementById('lmNota');
    if (nota) {
      nota.textContent = has
        ? 'Datos consultados para la clave ' + (data.licencia_key || '') + ' en el LM.'
        : 'Plan, tipo, vencimiento y límites provienen del License Manager; al crear la cuenta la licencia se valida contra el LM.';
    }
  }

  function consultarLm() {
    var key = document.getElementById('eLicKey').value.trim().toUpperCase();
    if (!key) {
      return Promise.reject(new Error('Ingresa la clave de licencia para consultar el LM.'));
    }
    return window.balansoftApi('/panel/verificar-licencia', {
      method: 'POST',
      body: { licencia_key: key },
    }).then(function (verify) {
      if (!verify || verify.valida !== true) {
        throw new Error(
          (verify && verify.message) || 'La licencia no es válida en el LM del servidor.'
        );
      }
      lmData = {
        licencia_key: key,
        tier: verify.tier || 'DEMO',
        plan_type: verify.plan_type || null,
        expires_at: verify.expires_at || null,
        client_name: (verify.features && verify.features.client_name) || null,
        distributor_name: (verify.features && verify.features.distributor_name) || null,
        max_equipos: lmMaxEquipos(verify),
        max_usuarios: lmMaxUsuarios(verify),
      };
      fillLmBlock(lmData);
      return lmData;
    });
  }

  var btnLmCheck = document.getElementById('btnLmCheck');
  var spinnerLm = document.getElementById('spinnerLm');
  btnLmCheck.addEventListener('click', function () {
    btnLmCheck.disabled = true;
    spinnerLm.classList.remove('d-none');
    consultarLm()
      .then(function () {
        hideModalMsg();
      })
      .catch(function (err) {
        showModalMsg('danger', err.message);
      })
      .finally(function () {
        btnLmCheck.disabled = false;
        spinnerLm.classList.add('d-none');
      });
  });

  document.getElementById('eLicKey').addEventListener('blur', function () {
    if (!this.value.trim()) return;
    consultarLm().catch(function () {
      /* En el blur solo se marca en el bloque; el error real sale al crear/guardar. */
      var nota = document.getElementById('lmNota');
      if (nota) nota.textContent = 'No se pudo consultar el LM con esa clave.';
    });
  });

  function setModo(nuevoModo) {
    var crear = nuevoModo === MODO.CREAR;
    modo = nuevoModo;

    ['wrapUsuario', 'wrapConfirmar'].forEach(function (id) {
      document.getElementById(id).classList.toggle('d-none', !crear);
    });
    ['wrapNombreComercial', 'wrapTelefono', 'wrapActiva', 'wrapDireccion', 'wrapLicStatus'].forEach(function (id) {
      document.getElementById(id).classList.toggle('d-none', crear);
    });

    setRequired('eNombreFiscal', true);
    setRequired('eRif', true);
    setRequired('eEmail', crear);
    setRequired('eUsuario', crear);
    setRequired('ePassword', crear);
    setRequired('eLicKey', crear);
    setRequired('eConfirmar', crear);

    document.getElementById('lblNombreFiscal').textContent = crear
      ? 'Nombre de la empresa'
      : 'Nombre fiscal';
    document.getElementById('lblEmail').textContent = crear
      ? 'Correo del administrador'
      : 'Email administrador';
    document.getElementById('lblPassword').textContent = crear
      ? 'Contraseña del administrador'
      : 'Nueva contraseña (opcional)';
    document.getElementById('pwHelp').textContent = crear
      ? 'Tú creas esta contraseña para el administrador de la estación.'
      : 'Déjala vacía para no cambiarla.';
    document.getElementById('btnGuardarLabel').textContent = crear
      ? 'Verificar licencia y crear cuenta'
      : 'Guardar cambios';

    document.getElementById('cuentaModalTitle').textContent = crear
      ? 'Registrar cuenta'
      : 'Editar cuenta';
  }

  /* ---------- Abrir modal: registrar (nueva cuenta) ---------- */
  function abrirModalCrear() {
    hideModalMsg();
    cuentaForm.reset();
    document.getElementById('eActiva').value = 'true';
    document.getElementById('eRif').value = 'J-';
    document.getElementById('eConfirmar').checked = false;
    document.getElementById('ePassword').value = '';
    document.getElementById('eLicKey').value = '';
    lmData = null;
    editKeyOriginal = '';
    fillLmBlock(null);
    setModo(MODO.CREAR);

    new bootstrap.Modal(cuentaModalEl).show();
    document.getElementById('eNombreFiscal').focus();
  }

  /* ---------- Abrir modal: editar cuenta existente ---------- */
  function abrirModalEditar(id) {
    hideModalMsg();
    spinnerOn(true);

    window.balansoftApi('/panel/cuentas/' + id)
      .then(function (d) {
        var lic = (d.licencias || [])[0];

        document.getElementById('eId').value = d.cuenta.id_cuenta;
        document.getElementById('eNombreFiscal').value = d.cuenta.nombre_fiscal || '';
        document.getElementById('eNombreComercial').value = d.cuenta.nombre_comercial || '';
        document.getElementById('eRif').value = d.cuenta.rif_nit || '';
        document.getElementById('eEmail').value = d.cuenta.email_admin || '';
        document.getElementById('eTelefono').value = d.cuenta.telefono || '';
        document.getElementById('eDireccion').value = d.cuenta.direccion || '';
        document.getElementById('eActiva').value = d.cuenta.activa ? 'true' : 'false';
        document.getElementById('eLicStatus').value = lic ? lic.licencia_status : 'ACTIVA';
        document.getElementById('eLicKey').value = lic ? lic.licencia_key : '';
        document.getElementById('ePassword').value = '';

        editKeyOriginal = (lic && lic.licencia_key) || '';
        var tier = (lic && lic.licencia_tier) || 'DEMO';
        lmData = {
          licencia_key: editKeyOriginal,
          tier: tier,
          plan_type: null,
          expires_at: lic && lic.fecha_expira ? lic.fecha_expira : null,
          client_name: null,
          distributor_name: null,
          max_equipos:
            lic && lic.max_equipos != null ? lic.max_equipos : (tier === 'CENTRAL' ? 3 : 1),
          max_usuarios:
            lic && lic.max_usuarios != null ? lic.max_usuarios : (tier === 'CENTRAL' ? 10 : 1),
        };
        fillLmBlock(lmData);

        setModo(MODO.EDITAR);
        new bootstrap.Modal(cuentaModalEl).show();
      })
      .catch(function (err) {
        apiErrorBox(modalAlert, err);
      })
      .finally(function () {
        spinnerOn(false);
      });
  }

  document.getElementById('btnNuevaCuenta').addEventListener('click', abrirModalCrear);

  /* ---------- Submit del modal registrar/editar ---------- */
  cuentaForm.addEventListener('submit', function (ev) {
    ev.preventDefault();
    if (modo === MODO.CREAR) {
      crearCuenta();
    } else {
      guardarEdicion();
    }
  });

  /* ---------- Crear cuenta: validar licencia en el mismo modal y registrar ---------- */
  function crearCuenta() {
    hideModalMsg();
    if (!document.getElementById('eConfirmar').checked) {
      showModalMsg(
        'danger',
        'Debes confirmar que la clave de licencia pertenece a un cliente antes de crear la cuenta.'
      );
      return;
    }

    spinnerOn(true);
    showModalMsg(
      'info',
      '<i class="bi bi-shield-check me-2"></i>Verificando la disponibilidad de la licencia contra el LM…'
    );

    consultarLm()
      .then(function (data) {
        showModalMsg(
          'success',
          '<i class="bi bi-check-circle me-2"></i>Licencia disponible (plan: ' +
            esc(data.tier) +
            ', tipo: ' +
            planTypeLabel(data.plan_type) +
            ', vence: ' +
            window.BalansoftHelpers.fmtFecha(data.expires_at) +
            '). Dando de alta la cuenta…'
        );

        var payload = {
          empresa_nombre: document.getElementById('eNombreFiscal').value.trim(),
          empresa_rif: document.getElementById('eRif').value.trim(),
          email_admin: document.getElementById('eEmail').value.trim().toLowerCase(),
          telefono: null,
          direccion: null,
          usuario_nombre: document.getElementById('eUsuario').value.trim(),
          password: document.getElementById('ePassword').value,
          licencia_key: data.licencia_key,
          licencia_tier: data.tier,
          fecha_expira: data.expires_at
            ? new Date(data.expires_at).toISOString()
            : new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
          max_equipos: data.max_equipos,
          max_usuarios: data.max_usuarios,
        };

        return window.balansoftApi('/auth/register', {
          method: 'POST',
          body: payload,
          auth: false,
        });
      })
      .then(function (reg) {
        if (window.showToast) {
          window.showToast('Cuenta creada correctamente', 'success');
        }
        listarCuentas();
        bootstrap.Modal.getInstance(cuentaModalEl).hide();
      })
      .catch(function (err) {
        showModalMsg('danger', err.message);
      })
      .finally(function () {
        spinnerOn(false);
      });
  }

  /* ---------- Editar cuenta existente ---------- */
  function guardarEdicion() {
    hideModalMsg();

    var id = document.getElementById('eId').value;
    var key = document.getElementById('eLicKey').value.trim().toUpperCase();
    var pw = document.getElementById('ePassword').value;

    spinnerOn(true);
    var preparado = key && key !== editKeyOriginal ? consultarLm() : Promise.resolve();

    preparado
      .then(function () {
        var payload = {
          nombre_fiscal: document.getElementById('eNombreFiscal').value.trim() || null,
          nombre_comercial: document.getElementById('eNombreComercial').value.trim() || null,
          rif_nit: document.getElementById('eRif').value.trim() || null,
          email_admin: document.getElementById('eEmail').value.trim().toLowerCase() || null,
          telefono: document.getElementById('eTelefono').value.trim() || null,
          direccion: document.getElementById('eDireccion').value.trim() || null,
          activa: document.getElementById('eActiva').value === 'true',
          licencia_status: document.getElementById('eLicStatus').value,
        };
        if (key) payload.licencia_key = key;
        if (lmData) {
          payload.licencia_tier = lmData.tier;
          payload.max_equipos = lmData.max_equipos;
          payload.max_usuarios = lmData.max_usuarios;
          if (lmData.expires_at) {
            payload.fecha_expira = new Date(lmData.expires_at).toISOString();
          }
        }
        if (pw) payload.password = pw;

        return window.balansoftApi('/panel/cuentas/' + id, { method: 'PUT', body: payload });
      })
      .then(function () {
        if (window.showToast) {
          window.showToast('Cuenta actualizada correctamente', 'success');
        }
        listarCuentas();
        bootstrap.Modal.getInstance(cuentaModalEl).hide();
      })
      .catch(function (err) {
        showModalMsg('danger', err.message);
      })
      .finally(function () {
        spinnerOn(false);
      });
  }

  /* ---------- Listado (CRUD) ---------- */
  function listarCuentas() {
    var body = document.getElementById('cuentasBody');
    var alert = document.getElementById('cuentasAlert');
    clearBox(alert);
    body.innerHTML =
      '<tr><td colspan="5" class="text-center text-secondary py-4">' +
      '<span class="spinner-border spinner-border-sm me-2"></span>Cargando cuentas…</td></tr>';

    window.balansoftApi('/panel/cuentas')
      .then(function (cuentas) {
        body.innerHTML = '';
        document.getElementById('cuentasEmpty').classList.toggle('d-none', cuentas.length > 0);
        cuentas.forEach(function (c) {
          var tr = document.createElement('tr');
          tr.className = 'row-account';
          var id = c.id_cuenta;
          tr.innerHTML =
            '<td><strong>' + esc(c.nombre_fiscal || '—') + '</strong></td>' +
            '<td>' + esc(c.rif_nit || '—') + '</td>' +
            '<td>' + esc(c.email_admin || '—') + '</td>' +
            '<td>' +
            (c.activa
              ? '<span class="badge bg-success badge-lg">Activa</span>'
              : '<span class="badge bg-danger badge-lg">Inactiva</span>') +
            '</td>' +
            '<td class="text-end">' +
            '<div class="d-flex justify-content-end align-items-center gap-1">' +
            '<button class="btn btn-outline-brand btn-sm" data-lic="' + id + '" title="Verificar vigencia de licencia">' +
            '<i class="bi bi-key"></i></button>' +
            '<button class="btn btn-outline-brand btn-sm" data-edit="' + id + '" title="Editar cuenta">' +
            '<i class="bi bi-pencil"></i> Editar</button>' +
            '<i class="bi bi-chevron-right text-secondary"></i>' +
            '</div></td>';

          var btnLic = tr.querySelector('button[data-lic]');
          btnLic.addEventListener('click', function (e) {
            e.stopPropagation();
            verificarLicencia(btnLic.getAttribute('data-lic'));
          });
          var btnEdit = tr.querySelector('button[data-edit]');
          btnEdit.addEventListener('click', function (e) {
            e.stopPropagation();
            abrirModalEditar(btnEdit.getAttribute('data-edit'));
          });
          tr.addEventListener('click', function () {
            detalleCuenta(id);
          });
          body.appendChild(tr);
        });
      })
      .catch(function (err) {
        body.innerHTML = '';
        apiErrorBox(alert, err);
      });
  }

  /* ---------- Detalle de cuenta (clic en la fila) ---------- */
  function detalleCuenta(id) {
    var bodyModal = document.getElementById('detalleModalBody');
    var title = document.getElementById('detalleModalTitle');
    title.textContent = 'Detalle de la cuenta';
    bodyModal.innerHTML =
      '<div class="text-center py-4"><span class="spinner-border spinner-border-sm me-2"></span>Cargando…</div>';
    var modal = new bootstrap.Modal(document.getElementById('detalleModal'));
    modal.show();

    window.balansoftApi('/panel/cuentas/' + id)
      .then(function (d) {
        var licencias = (d.licencias || [])
          .map(function (l) {
            return (
              '<li class="list-group-item d-flex justify-content-between align-items-center">' +
              '<div><strong>' + esc(l.licencia_key) + '</strong><br>' +
              '<span class="small text-secondary">' + esc(l.licencia_tier) +
              ' · vence ' + window.BalansoftHelpers.fmtFecha(l.fecha_expira) + '</span></div>' +
              '<span class="badge bg-' +
              window.BalansoftHelpers.badgeStatus(l.licencia_status) +
              ' badge-lg">' + esc(l.licencia_status) + '</span>' +
              '</li>'
            );
          })
          .join('') || '<li class="list-group-item text-secondary">Sin licencias</li>';

        var credenciales = (d.credenciales || [])
          .map(function (c) {
            return (
              '<li class="list-group-item d-flex justify-content-between align-items-center">' +
              '<div>' + esc(c.email) + '<br>' +
              '<span class="small text-secondary">' + esc(c.rol_global) + '</span></div>' +
              (c.activo
                ? '<span class="badge bg-success">Activo</span>'
                : '<span class="badge bg-danger">Inactivo</span>') +
              '</li>'
            );
          })
          .join('') || '<li class="list-group-item text-secondary">Sin credenciales</li>';

        bodyModal.innerHTML =
          '<div class="mb-3">' +
          '<h6 class="mb-1">' + esc(d.cuenta.nombre_fiscal || '—') + '</h6>' +
          '<div class="text-secondary small">RIF/NIT: ' + esc(d.cuenta.rif_nit || '—') +
          ' · Admin: ' + esc(d.cuenta.email_admin || '—') +
          ' · Equipos: <strong>' + (d.total_dispositivos || 0) + '</strong></div>' +
          '</div>' +
          '<h6 class="text-uppercase small text-secondary">Licencias</h6>' +
          '<ul class="list-group mb-3">' + licencias + '</ul>' +
          '<h6 class="text-uppercase small text-secondary">Credenciales</h6>' +
          '<ul class="list-group">' + credenciales + '</ul>';
      })
      .catch(function (err) {
        bodyModal.innerHTML =
          '<div class="alert alert-danger alert-box mb-0">' + esc(err.message) + '</div>';
      });
  }

  /* ---------- Verificación rápida de la vigencia por cliente ---------- */
  function verificarLicencia(id) {
    var bodyModal = document.getElementById('licenciaModalBody');
    var title = document.getElementById('licenciaModalTitle');
    title.textContent = 'Vigencia de licencia';
    bodyModal.innerHTML =
      '<div class="text-center py-4"><span class="spinner-border spinner-border-sm me-2"></span>Consultando…</div>';
    var modal = new bootstrap.Modal(document.getElementById('licenciaModal'));
    modal.show();

    window.balansoftApi('/panel/cuentas/' + id)
      .then(function (d) {
        var cuenta = d.cuenta || {};
        var lic = (d.licencias || [])[0];
        if (!lic) {
          bodyModal.innerHTML =
            '<div class="text-secondary small">' +
            '<strong>' + esc(cuenta.nombre_fiscal || '—') + '</strong> no tiene ninguna ' +
            'licencia registrada. Puedes asignarle una desde "Editar".</div>';
          return;
        }
        var vig = vigenciaInfo(lic);
        bodyModal.innerHTML =
          '<div class="mb-2 d-flex justify-content-between align-items-center gap-2">' +
          '<div><h6 class="mb-0">' + esc(cuenta.nombre_fiscal || '—') + '</h6>' +
          '<span class="small text-secondary">' + esc(lic.licencia_key) + '</span></div>' +
          '<span class="badge ' + vig.cls + ' badge-lg">' + vig.label + '</span>' +
          '</div>' +
          '<ul class="list-unstyled small mb-0">' +
          '<li><strong>Estado registrado:</strong> ' + esc(lic.licencia_status || '—') + '</li>' +
          '<li><strong>Vence:</strong> ' + window.BalansoftHelpers.fmtFecha(lic.fecha_expira) + '</li>' +
          '<li><strong>Tier:</strong> ' + esc(lic.licencia_tier || '—') + '</li>' +
          '<li><strong>Máx. equipos:</strong> ' + (lic.max_equipos != null ? lic.max_equipos : '—') + '</li>' +
          '<li><strong>Máx. usuarios:</strong> ' + (lic.max_usuarios != null ? lic.max_usuarios : '—') + '</li>' +
          '<li><strong>Detalle:</strong> ' + vig.detail + '</li>' +
          '</ul>';
      })
      .catch(function (err) {
        bodyModal.innerHTML =
          '<div class="alert alert-danger alert-box mb-0">' + esc(err.message) + '</div>';
      });
  }

  function vigenciaInfo(lic) {
    var est = (lic.licencia_status || 'ACTIVA').toUpperCase();
    var fecha = lic.fecha_expira ? new Date(lic.fecha_expira) : null;
    var hoy = new Date();
    hoy.setHours(0, 0, 0, 0);
    if (!fecha || isNaN(fecha.getTime())) {
      return {
        label: 'Sin vigencia',
        cls: 'bg-secondary',
        detail: 'La licencia no tiene fecha de expiración.',
      };
    }
    var diff = Math.round((fecha.getTime() - hoy.getTime()) / 86400000);
    if (est !== 'ACTIVA') {
      return {
        label: est,
        cls: window.BalansoftHelpers.badgeStatus(est),
        detail: 'La licencia está rechazada o inactiva (estatus ' + est + ').',
      };
    }
    if (diff < 0) {
      return {
        label: 'Vencida',
        cls: 'bg-danger',
        detail: 'La licencia venció el ' + window.BalansoftHelpers.fmtFecha(fecha) + '.',
      };
    }
    if (diff <= 30) {
      return {
        label: 'Próxima a vencer',
        cls: 'bg-warning',
        detail: 'Vence en ' + diff + ' día(s): ' + window.BalansoftHelpers.fmtFecha(fecha) + '.',
      };
    }
    return {
      label: 'Válida',
      cls: 'bg-success',
      detail:
        'Válida hasta el ' + window.BalansoftHelpers.fmtFecha(fecha) +
        ' (' + diff + ' días restantes).',
    };
  }

  document.getElementById('btnRefresh').addEventListener('click', listarCuentas);
  listarCuentas();
})();