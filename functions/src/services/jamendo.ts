import axios from 'axios';
import { ReelTone } from '../types';
import config from '../config';

export interface JamendoTrack {
  id: number;
  name: string;
  duration: number;
  audio: string;  // Stream URL
  audiodownload: string;  // Download URL
  tags: string[];
}

export class JamendoService {
  private readonly apiKey: string;
  private readonly baseURL = 'https://api.jamendo.com/v3.0';

  constructor() {
    this.apiKey = config.jamendo.apiKey;
    console.log('🎵 JamendoService initialized');
    console.log('API Key present:', !!this.apiKey);
    if (!this.apiKey) {
      console.error('❌ Jamendo API key is missing!');
    }
  }

  async fetchBackgroundMusic(tone: ReelTone, mood: string): Promise<{ url: string; duration: number }> {
    try {
      console.log('🎵 Starting Jamendo background music search with:', { tone, mood });
      
      if (!this.apiKey) {
        throw new Error('Jamendo API key is not configured');
      }

      // Try with different search strategies
      const searchStrategies = [
        // First try: Use tone-based tags
        async () => this.searchTrack(this.getToneTags(tone)),
        // Second try: Use mood
        async () => this.searchTrack([mood.toLowerCase(), 'instrumental']),
        // Last try: Basic instrumental search
        async () => this.searchTrack(['instrumental', 'background'])
      ];

      for (const strategy of searchStrategies) {
        const track = await strategy();
        if (track) {
          return {
            url: track.audiodownload || track.audio,
            duration: track.duration
          };
        }
      }

      throw new Error('No suitable background music found');
    } catch (error: any) {
      console.error('Error in fetchBackgroundMusic:', error);
      throw new Error(`Failed to fetch background music: ${error.message}`);
    }
  }

  private async searchTrack(tags: string[]): Promise<JamendoTrack | null> {
    // Basic parameters according to Jamendo API docs
    const params = new URLSearchParams({
      client_id: this.apiKey,
      format: 'json',
      limit: '100',                 // Get more results
      include: 'musicinfo',         // Include music info
      orderby: 'popularity_total',  // Sort by popularity
      audioformat: 'mp32',          // Specify audio format
      tags: tags.join('+')         // Join tags with + as per API spec
    });

    const url = `${this.baseURL}/tracks/`;
    console.log('🔍 Searching Jamendo with tags:', tags);

    try {
      const response = await axios.get(`${url}?${params.toString()}`);
      console.log('API Response status:', response.status);
      
      if (response.status !== 200) {
        console.error('❌ Jamendo API error:', response.status, response.data);
        return null;
      }

      console.log('Found tracks:', response.data.results?.length || 0);

      const results = response.data.results || [];
      if (results.length === 0) {
        console.log('❌ No tracks found');
        return null;
      }

      // Filter for valid tracks with audio URLs and appropriate duration
      const validTracks = results.filter((track: JamendoTrack) => {
        const hasAudio = track.audiodownload || track.audio;
        const validDuration = track.duration >= 30 && track.duration <= 300; // Between 30s and 5min
        return hasAudio && validDuration;
      });

      if (validTracks.length === 0) {
        console.log('❌ No valid tracks found after filtering');
        return null;
      }

      // Select a random track from top 10 most popular
      const topTracks = validTracks.slice(0, 10);
      const selectedTrack = topTracks[Math.floor(Math.random() * topTracks.length)];
      
      console.log('✅ Selected track:', {
        id: selectedTrack.id,
        name: selectedTrack.name,
        duration: selectedTrack.duration,
        tags: selectedTrack.tags
      });

      return selectedTrack;
    } catch (error: any) {
      console.error('❌ Error searching tracks:', error);
      if (error.response) {
        console.log('API Error Response:', error.response.data);
      }
      return null;
    }
  }

  private getToneTags(tone: ReelTone): string[] {
    switch (tone) {
      case 'dramatic':
        return ['dramatic', 'instrumental', 'epic'];
      case 'professional':
        return ['corporate', 'instrumental', 'background'];
      case 'casual':
        return ['upbeat', 'instrumental', 'positive'];
      default:
        return ['instrumental', 'background'];
    }
  }
} 