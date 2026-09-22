/* Cliente HTTP del panel administrativo contra la API del servidor. */
(function () {
  function token() {
    return localStorage.getItem('balansoft_panel_token');
  }

  async function balansoftApi(path, opts) {
    var options = opts || {};
    var headers = {};
    if (options.auth !== false) {
      var t = token();
      if (t) headers['Authorization'] = 'Bearer ' + t;
    }
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';

    var controller = new AbortController();
    var timer = setTimeout(function () {
      controller.abort();
    }, options.timeout || 20000);

    var res;
    try {
      res = await fetch(window.BalansoftConfig.apiBase + path, {
        method: options.method || 'GET',
        headers: headers,
        body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
        signal: controller.signal,
      });
    } catch (err) {
      clearTimeout(timer);
      throw new Error(
        'No se pudo contactar la API (' + window.BalansoftConfig.apiBase + '). Verifica el servidor.'
      );
    }
    clearTimeout(timer);

    var data = {};
    try {
      data = await res.json();
    } catch (_) {
      data = {};
    }

    if (!res.ok) {
      var message = 'Error ' + res.status;
      if (data && data.detail) {
        message =
          typeof data.detail === 'string'
            ? data.detail
            : JSON.stringify(data.detail);
      }
      if (res.status === 401) {
        panelLogoutRedirect();
      }
      var err = new Error(message);
      err.status = res.status;
      throw err;
    }
    return data;
  }

  function panelLogoutRedirect() {
    localStorage.removeItem('balansoft_panel_token');
    localStorage.removeItem('balansoft_panel_user');
    if (!/index\.html/.test(window.location.pathname)) {
      window.location.replace('index.html');
    }
  }

  function fmtFecha(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return iso;
    return d.toLocaleDateString('es-VE', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
  }

  function badgeStatus(status) {
    var map = {
      ACTIVA: 'success',
      VENCIDA: 'warning',
      SUSPENDIDA: 'danger',
      EXPIRADA: 'danger',
      true: 'success',
      false: 'danger',
    };
    var cls = map[String(status).toUpperCase()] || 'secondary';
    return cls;
  }

  window.balansoftApi = balansoftApi;
  window.BalansoftHelpers = { fmtFecha: fmtFecha, badgeStatus: badgeStatus };
})();