import type {
  NuclearPlugin,
  NuclearPluginAPI,
  StreamingProvider,
  YtdlpSearchResult,
} from '@nuclearplayer/plugin-sdk';

const PROVIDER_ID = 'jiosaavn-streaming';

const buildQuotedQuery = (artist: string, title: string): string => {
  const safeTitle = title.replace(/"/g, '');
  return `${artist} "${safeTitle}"`;
};

const dedupeById = (results: YtdlpSearchResult[]): YtdlpSearchResult[] => {
  const seen = new Set<string>();
  return results.filter((result) => {
    if (seen.has(result.id)) {
      return false;
    }
    seen.add(result.id);
    return true;
  });
};

const valueOrEmpty = (
  outcome: PromiseSettledResult<YtdlpSearchResult[]>,
): YtdlpSearchResult[] => {
  if (outcome.status === 'fulfilled') {
    return outcome.value;
  }
  return [];
};

const createProvider = (api: NuclearPluginAPI): StreamingProvider => ({
  id: PROVIDER_ID,
  kind: 'streaming',
  name: 'JioSaavn',
  description: 'JioSaavn streaming provider for Nuclear',

  searchForTrack: async (artist, title) => {
    const [quotedOutcome, plainOutcome] = await Promise.allSettled([
      api.Ytdlp.search(buildQuotedQuery(artist, title)),
      api.Ytdlp.search(`${artist} ${title}`),
    ]);

    if (
      quotedOutcome.status === 'rejected' &&
      plainOutcome.status === 'rejected'
    ) {
      throw quotedOutcome.reason;
    }

    const results = dedupeById([
      ...valueOrEmpty(quotedOutcome),
      ...valueOrEmpty(plainOutcome),
    ]);

    return results.map((result) => ({
      id: result.id,
      title: result.title,
      durationMs: result.duration ? result.duration * 1000 : undefined,
      thumbnail: result.thumbnail ?? undefined,
      failed: false,
      source: { provider: PROVIDER_ID, id: result.id },
    }));
  },

  getStreamUrl: async (candidateId) => {
    const info = await api.Ytdlp.getStream(candidateId);

    return {
      url: info.stream_url,
      protocol: 'https',
      durationMs: info.duration ? info.duration * 1000 : undefined,
      container: info.container ?? undefined,
      codec: info.codec ?? undefined,
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