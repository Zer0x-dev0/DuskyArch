import type { DashboardProvider, NuclearPlugin } from '@nuclearplayer/plugin-sdk';

const PROVIDER_ID = 'jiosaavn-dashboard';

const createProvider = (): DashboardProvider => ({
  id: PROVIDER_ID,
  kind: 'dashboard',
  name: 'JioSaavn',
  description: 'JioSaavn dashboard provider for Nuclear',
  capabilities: [
    'topTracks',
    'topArtists',
    'topAlbums',
    'editorialPlaylists',
    'newReleases',
  ],

  async fetchTopTracks() {
    return [];
  },

  async fetchTopArtists() {
    return [];
  },

  async fetchTopAlbums() {
    return [];
  },

  async fetchEditorialPlaylists() {
    return [];
  },

  async fetchNewReleases() {
    return [];
  },
});

const plugin: NuclearPlugin = {
  onEnable(api) {
    api.Providers.register(createProvider());
  },
  onDisable(api) {
    api.Providers.unregister(PROVIDER_ID);
  },
};

export default plugin;