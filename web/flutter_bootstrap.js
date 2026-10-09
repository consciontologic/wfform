{{flutter_js}}
{{flutter_build_config}}
// Package files stay flat. Only the verified cache identity is content-addressed.
const releasePath = '__RELEASE_BASE__';
const buildId = /^[a-f0-9]{64}$/.test(releasePath) ? releasePath : '';
const flutterConfiguration = {
  entrypointBaseUrl: '',
  assetBase: new URL('./', document.baseURI).href,
  canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
};
if (buildId) {
  document.documentElement.dataset.release = buildId;
  const reportRelease = () => navigator.serviceWorker?.controller?.postMessage({
    type: 'CLIENT_RELEASE', release: buildId,
  });
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.ready.then(reportRelease);
    navigator.serviceWorker.addEventListener('controllerchange', reportRelease);
    reportRelease();
  }
}
function showStartupError(error) {
  const failure = document.getElementById('startup-error');
  const details = document.getElementById('startup-error-details');
  if (details) details.textContent = String(error).slice(0, 300);
  if (failure) failure.hidden = false;
}
_flutter.loader.load({
  config: flutterConfiguration,
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine(flutterConfiguration);
      await appRunner.runApp();
      document.getElementById('startup-error')?.remove();
    } catch (error) {
      showStartupError(error);
    }
  }
}).catch(showStartupError);
