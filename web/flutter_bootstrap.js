{{flutter_js}}
{{flutter_build_config}}
// The builder stamps this path; development keeps ordinary local paths.
const releasePath = '__RELEASE_BASE__';
const releaseBase = releasePath.startsWith('__RELEASE_') ? '' : releasePath;
const flutterConfiguration = {
  entrypointBaseUrl: releaseBase,
  assetBase: new URL(releaseBase || './', document.baseURI).href,
  canvasKitBaseUrl: new URL(releaseBase + 'canvaskit/', document.baseURI).href,
};
if (releaseBase) {
  document.documentElement.dataset.release = releaseBase.split('/')[1];
  const reportRelease = () => navigator.serviceWorker?.controller?.postMessage({
    type: 'CLIENT_RELEASE', release: document.documentElement.dataset.release,
  });
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.ready.then(reportRelease);
    navigator.serviceWorker.addEventListener('controllerchange', reportRelease);
  }
}
function showStartupError(error) {
  const loading = document.getElementById('loading');
  if (loading) loading.textContent = 'wfform could not start. Reconnect and reload. ' + String(error).slice(0, 300);
}
_flutter.loader.load({
  config: flutterConfiguration,
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine(flutterConfiguration);
      await appRunner.runApp();
      document.getElementById('loading')?.remove();
    } catch (error) {
      showStartupError(error);
    }
  }
}).catch(showStartupError);
