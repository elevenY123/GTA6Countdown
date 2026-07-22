const fs = require('fs');

const required = [
  'GTA6Countdown/Services/NewsAPIClient.swift',
  'GTA6Countdown/Services/NewsRepository.swift',
  'GTA6Countdown/Services/ImageCache.swift',
  'GTA6CountdownTests/NewsRepositoryTests.swift',
  'GTA6CountdownTests/URLProtocolStub.swift',
  'GTA6CountdownTests/ImageCacheTests.swift',
];

for (const file of required) {
  if (!fs.existsSync(file)) throw new Error(`missing ${file}`);
}

const api = fs.readFileSync(required[0], 'utf8');
const repository = fs.readFileSync(required[1], 'utf8');
const image = fs.readFileSync(required[2], 'utf8');
const validator = fs.readFileSync('GTA6Countdown/Shared/News/NewsPayloadValidator.swift', 'utf8');

if (!api.includes('URLSession') || !api.includes('endpoint')) throw new Error('API client is not injected');
if (!api.includes('200..<300') || !api.includes('NewsPayloadValidator.validate')) throw new Error('API validation missing');
if (!validator.includes('schemaVersion') || !validator.includes('canonicalTopicKey')) throw new Error('shared payload validation missing');
if (!repository.includes('inFlight') || !repository.includes('WidgetReloading')) throw new Error('repository resilience missing');
if (!repository.includes('SharedCache') || !repository.includes('lastUpdatedAt')) throw new Error('repository cache contract missing');
if (!repository.includes('lastGoodPayload')) throw new Error('in-memory last-good fallback missing');
if (!repository.includes('updatedAt') || !repository.includes('freshestPayload')) throw new Error('stale disk precedence missing');
if (!repository.includes('import WidgetKit')) throw new Error('production widget integration missing');
if (!repository.includes('final class SystemWidgetReloader')) throw new Error('concrete widget reloader missing');
if (!repository.includes('WidgetCenter.shared.reloadTimelines(ofKind: kind)')) throw new Error('kind-scoped WidgetCenter reload missing');
if (!repository.includes('widgetReloader: WidgetReloading = SystemWidgetReloader()')) {
  throw new Error('repository production default is not the concrete widget reloader');
}
if (!image.includes('SHA256') || !image.includes('maximumDiskSize')) throw new Error('bounded safe image cache missing');
if (!image.includes('inFlight')) throw new Error('image request coalescing missing');
if (!image.includes('maximumResponseSize') || !image.includes('download(from:')) throw new Error('response memory bound missing');
if (!image.includes('cacheDirectoryName') || !image.includes('isOwnedCacheFile')) throw new Error('owned cache scope missing');
if (!image.includes('maximumConcurrentDownloads') || !image.includes('DownloadLimiter')) throw new Error('download concurrency bound missing');
if (!image.includes('withTaskCancellationHandler') || !image.includes('waiters')) throw new Error('waiter cancellation missing');
if (!image.includes('download.task.cancel()')) throw new Error('unobserved shared download is not cancelled');
if (!image.includes('startupMaintenanceTask') || !image.includes('waitForMaintenance')) throw new Error('async startup maintenance missing');
if (!image.includes('Task.detached')) throw new Error('startup maintenance is not off the caller executor');
if (!image.includes('trackedDiskSize') || !image.includes('diskEntries')) throw new Error('incremental disk accounting missing');
if (!image.includes('enum StartupMaintenanceResult') || !image.includes('case failure')) throw new Error('maintenance failure is collapsed');
if (!image.includes('inventoryEstablished') || !image.includes('prepareInventoryForWrite')) throw new Error('writes are not gated on accurate inventory');
if (!image.includes('scheduleMaintenanceRetry')) throw new Error('failed maintenance is not retried before later writes');
if (!image.includes('ImageCacheMaintenanceOperations')) throw new Error('maintenance failures are not testable');
if (!image.includes('enum PersistResult') || !image.includes('case notCacheable')) throw new Error('persist result is ambiguous');
if (!image.includes('prepareCapacityForWrite')) throw new Error('capacity is not reserved before commit');
const dataMethod = image.slice(image.indexOf('func data(for:'), image.indexOf('private func reserveDownload'));
if (dataMethod.includes('maintainCache')) throw new Error('request path performs a full-directory scan');

console.log('Task 4 service contract validated.');
