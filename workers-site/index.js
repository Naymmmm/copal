import { getAssetFromKV } from '@cloudflare/kv-asset-handler'

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event))
})

async function handleRequest(event) {
  try {
    return await getAssetFromKV(event)
  } catch (e) {
    return new Response('Not Found', { status: 404 })
  }
}