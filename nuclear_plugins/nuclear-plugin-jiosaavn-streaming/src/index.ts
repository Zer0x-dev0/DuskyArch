import type { StreamingProvider, NuclearPlugin } from '@nuclearplayer/plugin-sdk';

const PROVIDER_ID = 'jiosaavn-streaming';

const buildQuotedQuery = (query: string): string => {
  const escaped = query.replace(/"/g, '\\"');
  return `"${escaped}"`;
};

const dedupeById = (results: any[]): any[] => {
  const seen = new Set<string>();
  return results.filter((result) => {
    if (seen.has(result.id)) {
      return false;
    }
    seen.add(result.id);
    return true;
  });
};

const createProvider = (api: any): StreamingProvider => ({
  id: PROVIDER_ID,
  name: 'JioSaavn',
  description: 'JioSaavn streaming provider for Nuclear',
  searchForTrack: async ({ artist, name, album, year }) => {
    const quotedQuery = buildQuotedQuery([artist, name].filter(Boolean).join(' '));
    const plainQuery = [artist, name, album, year].filter(Boolean).join(' ');

    const [quotedResults, plainResults] = await Promise.all([
      api.Ytdlp.search(quotedQuery, 10),
      api.Ytdlp.search(plainQuery, 10),
    ]);

    const results = dedupeById([...quotedResults, ...plainResults]);

    return results.map((result) => ({
      id: result.id,
      title: result.title,
      thumbnail: result.thumbnail,
      artist: result.artist,
      duration: result.duration,
    }));
  },
  getStreamUrl: async (track) => {
    return api.Ytdlp.getStream(track.id, track.title);
  },
});

const plugin: NuclearPlugin = {
  onEnable: (api) => {
    api.Providers.register(createProvider(api));
  },
  onDisable: (api) => {
    api.Providers.unregister(PROVIDER_ID);
  },
};

export default plugin;
