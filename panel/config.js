/* Configuración del panel administrativo Balansoft (BALASOFT-UI).
 * El panel habla contra la API del SERVIDOR (APP_ROLE=server).
 * La URL base se puede cambiar desde el icono de ajustes del login; el valor
 * queda guardado en localStorage bajo la clave `balansoft_panel_api`.
 */
(function () {
  var STORE_API = 'balansoft_panel_api_v2';
  var DEFAULT_API_BASE = 'http://127.0.0.1:8001/api/v1';

  window.BalansoftConfig = {
    DEFAULT_API_BASE: DEFAULT_API_BASE,
    get apiBase() {
      var saved = localStorage.getItem(STORE_API);
      return saved && saved.length ? saved : DEFAULT_API_BASE;
    },
    set apiBase(url) {
      localStorage.setItem(STORE_API, String(url || '').replace(/\/+$/, ''));
    },
  };
})();