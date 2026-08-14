import type {
  NuclearPlugin,
  NuclearPluginAPI,
  StreamCandidate,
  StreamingProvider,
} from '@nuclearplayer/plugin-sdk';
import { decryptDesEcb } from './des';

const PROVIDER_ID = 'jiosaavn-streaming';
const API_BASE = 'https://www.jiosaavn.com/api.php';
const DES_KEY = new TextEncoder().encode('38346591');

const callApi = async (
  api: NuclearPluginAPI,
  params: Record<string, string>,
): Promise<any> => {
  const query = new URLSearchParams({
    __call: params.__call,
    _format: 'json',
    _marker: '0',
    ctx: 'web6dot0',
    cc: 'in',
    ...params,
  });
  const res = await api.Http.fetch(`${API_BASE}?${query}`, {
    headers: { 'User-Agent': 'Mozilla/5.0' },
  });
  if (!res.ok) {
    throw new Error(`JioSaavn API error ${res.status}`);
  }
  return res.json();
};

const buildQuotedQuery = (artist: string, title: string): string => {
  const safeTitle = title.replace(/"/g, '');
  return `${artist} "${safeTitle}"`;
};

const valueOrEmpty = (
  outcome: PromiseSettledResult<any>,
): any[] => {
  if (outcome.status === 'fulfilled') {
    return outcome.value?.results ?? [];
  }
  return [];
};

const decryptMediaUrl = (encrypted: string): string => {
  const ciphertext = Uint8Array.from(atob(encrypted), (c) => c.charCodeAt(0));
  const plain = new TextDecoder().decode(decryptDesEcb(ciphertext, DES_KEY));
  return plain.replace('_96.mp4', '_320.mp4');
};

const createProvider = (api: NuclearPluginAPI): StreamingProvider => ({
  id: PROVIDER_ID,
  kind: 'streaming',
  name: 'JioSaavn',

  searchForTrack: async (artist, title) => {
    const [quotedOutcome, plainOutcome] = await Promise.allSettled([
      callApi(api, { __call: 'search.getResults', q: buildQuotedQuery(artist, title), n: '10' }),
      callApi(api, { __call: 'search.getResults', q: `${artist} ${title}`, n: '10' }),
    ]);

    if (
      quotedOutcome.status === 'rejected' &&
      plainOutcome.status === 'rejected'
    ) {
      throw quotedOutcome.reason;
    }

    const results = [...valueOrEmpty(quotedOutcome), ...valueOrEmpty(plainOutcome)];

    const seen = new Set<string>();
    const candidates: StreamCandidate[] = [];
    for (const song of results) {
      const id = String(song.id);
      if (seen.has(id)) {
        continue;
      }
      seen.add(id);
      candidates.push({
        id,
        title: song.title ?? song.song,
        durationMs: parseInt(song.duration ?? '0', 10) * 1000 || undefined,
        thumbnail: song.image ?? undefined,
        failed: false,
        source: { provider: PROVIDER_ID, id },
      });
    }

    return candidates;
  },

  getStreamUrl: async (candidateId) => {
    const data = await callApi(api, { __call: 'song.getDetails', pids: candidateId });
    const song = data?.songs?.[0];
    if (!song?.encrypted_media_url) {
      throw new Error('No stream url for song');
    }

    return {
      url: decryptMediaUrl(song.encrypted_media_url),
      protocol: 'https',
      container: 'mp4',
      codec: 'aac',
      durationMs: parseInt(song.duration ?? '0', 10) * 1000 || undefined,
      source: { provider: PROVIDER_ID, id: candidateId },
    };
  },
});

const plugin: NuclearPlugin = {
  onEnable(api: NuclearPluginAPI) {
    api.Providers.register(createProvider(api));
  },

  onDisable(api: NuclearPluginAPI) {
    api.Providers.unregister(PROVIDER_ID);
  },
};

export default plugin;
