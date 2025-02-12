import { VideoScene, SceneMedia, PixabayMedia, ReelTone } from '../types';
import config from '../config';
import os from 'os';
import path from 'path';
import fs from 'fs';
import axios from 'axios';

export interface PixabayAudioTrack {
  id: number;
  url: string;
  duration: number;
  title: string;
  description: string;
}

export class PixabayService {
  private readonly apiKey: string;
  private readonly videoBaseURL = 'https://pixabay.com/api/videos/';
  private readonly imageBaseURL = 'https://pixabay.com/api/';
  private readonly audioBaseURL = 'https://pixabay.com/api/audio/';
  private readonly tempDir: string;

  constructor() {
    this.apiKey = config.pixabay.apiKey;
    this.tempDir = os.tmpdir();
  }

  async fetchMediaForScene(scene: VideoScene): Promise<SceneMedia> {
    try {
      console.log('Starting media fetch for scene:', {
        description: scene.description,
        duration: scene.duration,
        visualType: scene.visualType
      });

      let primaryMedia: PixabayMedia[] = [];
      let searchAttempts = 0;
      const maxAttempts = 4;

      // Try different keyword combinations
      const keywordSets = [
        scene.primaryKeywords,
        scene.secondaryKeywords,
        [scene.mood.toLowerCase()],
        ['background', scene.visualType] // Generic fallback
      ];

      for (const keywords of keywordSets) {
        if (!keywords || keywords.length === 0) continue;
        searchAttempts++;

        try {
          primaryMedia = await this.fetchPrimaryMedia(
            scene.visualType,
            keywords,
            scene.duration
          );

          if (primaryMedia.length > 0) {
            console.log(`Found media using keywords:`, keywords);
            break;
          }
        } catch (error) {
          console.log(`Search attempt ${searchAttempts} failed with keywords:`, keywords, error);
          if (searchAttempts >= maxAttempts) {
            throw new Error('Exhausted all search attempts');
          }
        }
      }

      // If still no results, try one last time with very generic terms
      if (primaryMedia.length === 0) {
        console.log('Attempting final generic search...');
        try {
          primaryMedia = await this.fetchPrimaryMedia(
            'b-roll', // Default to b-roll
            ['video', 'background'],
            scene.duration
          );
        } catch (error) {
          console.log('Final generic search failed:', error);
        }
      }

      // Verify we have valid media
      if (primaryMedia.length === 0) {
        throw new Error(`No suitable media found for scene: ${scene.description}`);
      }

      // Download and validate media
      const validatedMedia = await this.downloadAndValidateMedia(primaryMedia, scene);
      console.log(`Successfully validated ${validatedMedia.length} media items`);

      if (validatedMedia.length === 0) {
        throw new Error('No media passed validation');
      }

      return {
        primary: validatedMedia,
        background: [],
        overlays: []
      };
    } catch (error: any) {
      console.error('Error fetching media for scene:', error);
      throw new Error(`Failed to fetch media: ${error.message}`);
    }
  }

  private async downloadAndValidateMedia(
    media: PixabayMedia[],
    scene: VideoScene
  ): Promise<PixabayMedia[]> {
    const validatedMedia: PixabayMedia[] = [];

    for (const item of media) {
      try {
        const localPath = path.join(this.tempDir, `media-${Date.now()}-${validatedMedia.length}${item.type === 'video' ? '.mp4' : '.jpg'}`);
        
        // Download the file
        await this.downloadFile(item.url, localPath);
        
        // Validate the downloaded file
        if (await this.validateDownloadedFile(localPath, item.type, scene)) {
          validatedMedia.push({
            ...item,
            localPath
          });
          console.log(`Successfully validated and stored media at: ${localPath}`);
        }
      } catch (error) {
        console.error(`Failed to download/validate media item:`, error);
      }
    }

    if (validatedMedia.length === 0) {
      throw new Error('No media items passed validation');
    }

    return validatedMedia;
  }

  private async downloadFile(url: string, localPath: string): Promise<void> {
    const response = await axios({
      method: 'get',
      url: url,
      responseType: 'stream'
    });

    return new Promise((resolve, reject) => {
      const writer = fs.createWriteStream(localPath);
      response.data.pipe(writer);
      writer.on('finish', resolve);
      writer.on('error', reject);
    });
  }

  private async validateDownloadedFile(
    localPath: string,
    type: 'video' | 'image',
    scene: VideoScene
  ): Promise<boolean> {
    try {
      const stats = await fs.promises.stat(localPath);
      
      // Check file size (min 100KB)
      if (stats.size < 102400) {
        console.log(`File too small: ${stats.size} bytes`);
        return false;
      }

      // Add more validation as needed
      return true;
    } catch (error) {
      console.error('File validation failed:', error);
      return false;
    }
  }

  private async fetchPrimaryMedia(
    visualType: string,
    keywords: string[],
    duration: number
  ): Promise<PixabayMedia[]> {
    switch (visualType) {
      case 'b-roll':
        return this.searchVideos(keywords, duration, null, 1920);
      case 'talking':
        return this.searchVideos(keywords, duration, 'people', 1920);
      case 'static':
        return this.searchImages(keywords, null, 1920);
      case 'overlay':
        return []; // Overlays handled separately
      default:
        throw new Error(`Unsupported visual type: ${visualType}`);
    }
  }

  private async searchVideos(
    keywords: string[],
    duration: number,
    category: string | null,
    minWidth: number,
    relaxedDuration: boolean = false
  ): Promise<PixabayMedia[]> {
    // Simplify search strategies to just two attempts
    const searchStrategies = [
      // Strategy 1: Main search with generic terms
      async () => {
        // Take only the most relevant keywords and add generic terms
        const searchTerms = keywords
          .slice(0, 2) // Take only first two keywords
          .map(k => k.toLowerCase())
          .filter(k => !k.includes(' ')) // Remove multi-word terms
          .filter(k => k.length > 2); // Remove very short terms

        // Add scene-related generic terms
        const genericTerms = ['scene', 'footage'];
        const finalTerms = [...new Set([...searchTerms, ...genericTerms])];
        
        console.log('🔍 Searching with terms:', finalTerms);
        const params = this.createVideoSearchParams(finalTerms, duration, 2, category, minWidth);
        return await this.executeVideoSearch(params);
      },
      // Strategy 2: Fallback with very generic terms
      async () => {
        console.log('⚠️ Using fallback search strategy');
        const fallbackTerms = ['background', 'scene', category || 'footage'];
        const params = this.createVideoSearchParams(fallbackTerms, duration, 5, null, minWidth);
        return await this.executeVideoSearch(params);
      }
    ];

    // Try each strategy in sequence until we find results
    for (const strategy of searchStrategies) {
      try {
        const results = await strategy();
        if (results.length > 0) {
          return results;
        }
      } catch (error) {
        console.log('Search strategy failed:', error);
        continue;
      }
    }

    throw new Error('No videos found after trying all search strategies');
  }

  private createVideoSearchParams(
    keywords: string[],
    duration: number,
    durationBuffer: number,
    category: string | null,
    minWidth: number
  ): URLSearchParams {
    const params = new URLSearchParams({
      key: this.apiKey,
      q: keywords.join(' '),
      per_page: '20',
      min_duration: Math.max(1, Math.floor(duration - durationBuffer)).toString(),
      max_duration: Math.ceil(duration + durationBuffer).toString(),
      order: 'relevance',
      min_width: minWidth.toString(),
      safesearch: 'true',
      video_type: 'film,animation'
    });

    if (category) {
      params.append('category', category);
    }

    console.log('🎥 Video search parameters:', {
      keywords,
      duration: `${duration - durationBuffer} to ${duration + durationBuffer}s`,
      category: category || 'any'
    });

    return params;
  }

  private async executeVideoSearch(params: URLSearchParams): Promise<PixabayMedia[]> {
    const response = await axios.get(`${this.videoBaseURL}?${params.toString()}`);
    
    if (response.status !== 200) {
      throw new Error(`Pixabay API error: ${response.status}`);
    }

    if (!response.data.hits?.length) {
      return [];
    }

    // Sort by relevance and duration match
    const sortedHits = response.data.hits
      .filter((hit: any) => hit.videos?.large?.url)
      .sort((a: any, b: any) => {
        // Prioritize relevance score if available
        if (a.relevance_score && b.relevance_score) {
          return b.relevance_score - a.relevance_score;
        }
        // Otherwise use duration match as a fallback
        const aDurationDiff = Math.abs(a.duration - parseFloat(params.get('min_duration')!));
        const bDurationDiff = Math.abs(b.duration - parseFloat(params.get('min_duration')!));
        return aDurationDiff - bDurationDiff;
      });

    // Return only the most relevant video
    return sortedHits.slice(0, 1).map((hit: any) => ({
      type: 'video',
      url: hit.videos.large.url,
      width: hit.width,
      height: hit.height
    }));
  }

  private async searchImages(
    keywords: string[],
    category: string | null,
    minWidth: number
  ): Promise<PixabayMedia[]> {
    const params = new URLSearchParams({
      key: this.apiKey,
      q: keywords.join('+'),
      per_page: '10',
      image_type: 'photo',
      orientation: 'horizontal',
      order: 'relevance',
      min_width: minWidth.toString(),
      safesearch: 'true'
    });

    if (category) {
      params.append('category', category);
    }

    const response = await axios.get(`${this.imageBaseURL}?${params.toString()}`);
    
    if (response.status !== 200 || !response.data.hits?.length) {
      throw new Error('No suitable images found');
    }

    return response.data.hits.map((hit: any) => ({
      type: 'image',
      url: hit.largeImageURL,
      width: hit.imageWidth,
      height: hit.imageHeight
    }));
  }

  async fetchBackgroundMusic(tone: ReelTone, mood: string): Promise<PixabayAudioTrack> {
    try {
      console.log('Starting background music search with:', { tone, mood });
      
      // Get keywords for search based on tone and mood
      const musicKeywords = this.getMusicKeywords(tone, mood);
      console.log('Generated music keywords:', musicKeywords);

      // Try different duration ranges from strict to relaxed
      const durationRanges = [
        { min: 25, max: 35 },  // Exact target
        { min: 20, max: 40 },  // Slightly relaxed
        { min: 15, max: 45 }   // Very relaxed
      ];

      // Try with mood-specific keywords first
      for (const range of durationRanges) {
        try {
          console.log(`Trying duration range: ${range.min}-${range.max} seconds with mood keywords`);
          const track = await this.searchAudioTrack(musicKeywords, range.min, range.max);
          if (track) {
            console.log('Found suitable track with mood keywords:', track);
            return track;
          }
        } catch (error) {
          console.log(`Search failed for range ${range.min}-${range.max} with mood keywords:`, error);
        }
      }

      // If no results with mood keywords, try tone-based keywords
      console.log('Trying tone-based background music search');
      const toneKeywords = this.getToneBasedMusicKeywords(tone);
      for (const range of durationRanges) {
        try {
          const track = await this.searchAudioTrack(toneKeywords, range.min, range.max);
          if (track) {
            console.log('Found suitable track with tone keywords:', track);
            return track;
          }
        } catch (error) {
          console.log(`Search failed for range ${range.min}-${range.max} with tone keywords:`, error);
        }
      }

      // Final fallback: use generic background music
      console.log('Using fallback generic background music search');
      const genericKeywords = this.getGenericMusicKeywords(tone);
      for (const range of durationRanges) {
        try {
          const track = await this.searchAudioTrack(genericKeywords, range.min, range.max);
          if (track) {
            console.log('Found generic track:', track);
            return track;
          }
        } catch (error) {
          console.log(`Generic search failed for range ${range.min}-${range.max}:`, error);
        }
      }

      // If all attempts fail, throw a specific error
      throw new Error('No suitable background music found after all attempts');
    } catch (error: any) {
      console.error('Error in fetchBackgroundMusic:', error);
      throw new Error(`Failed to fetch background music: ${error.message}`);
    }
  }

  private async searchAudioTrack(
    keywords: string[],
    minDuration: number,
    maxDuration: number
  ): Promise<PixabayAudioTrack | null> {
    const params = new URLSearchParams({
      key: this.apiKey,
      q: keywords.slice(0, 3).join('+'),
      min_duration: minDuration.toString(),
      max_duration: maxDuration.toString(),
      order: 'relevance'
    });

    console.log('Searching audio with params:', {
      keywords: keywords.slice(0, 3),
      minDuration,
      maxDuration
    });

    try {
      const response = await axios.get(`${this.audioBaseURL}?${params.toString()}`);
      
      if (response.status !== 200) {
        throw new Error(`Pixabay API error: ${response.status}`);
      }

      const hits = response.data.hits || [];
      if (hits.length === 0) {
        return null;
      }

      // Sort by duration match and validate URLs
      const targetDuration = (minDuration + maxDuration) / 2;
      const validTracks = hits
        .filter((track: any) => {
          // Check for required properties in the correct structure
          const hasAudio = track.audio_file || track.preview_url;  // Updated property names
          const hasDuration = typeof track.duration === 'number';
          if (!hasAudio || !hasDuration) {
            console.log('Skipping invalid track:', { 
              id: track.id, 
              hasAudio: !!hasAudio, 
              hasDuration: !!hasDuration,
              trackData: track  // Log the track data for debugging
            });
            return false;
          }
          return true;
        })
        .map((track: any) => ({
          id: track.id,
          url: track.audio_file || track.preview_url,  // Use the correct property
          duration: track.duration,
          title: track.title || '',
          description: track.description || ''
        }))
        .sort((a: PixabayAudioTrack, b: PixabayAudioTrack) => {
          const aDiff = Math.abs(a.duration - targetDuration);
          const bDiff = Math.abs(b.duration - targetDuration);
          return aDiff - bDiff;
        });

      if (validTracks.length === 0) {
        console.log('No valid tracks found after filtering');
        return null;
      }

      const selectedTrack = validTracks[0];
      
      // Final URL validation
      if (!selectedTrack.url) {
        console.error('Selected track has no URL:', selectedTrack);
        return null;
      }

      try {
        // Validate URL format
        new URL(selectedTrack.url);
        console.log('Selected valid track:', {
          id: selectedTrack.id,
          duration: selectedTrack.duration,
          url: selectedTrack.url
        });
        return selectedTrack;
      } catch (error) {
        console.error('Invalid URL format for track:', selectedTrack);
        return null;
      }
    } catch (error) {
      console.error('Error searching audio tracks:', error);
      return null;
    }
  }

  private getToneBasedMusicKeywords(tone: ReelTone): string[] {
    const keywords = new Set<string>();
    
    switch (tone) {
      case 'professional':
        keywords.add('corporate');
        keywords.add('business');
        keywords.add('background');
        keywords.add('instrumental');
        keywords.add('ambient');
        break;
      case 'casual':
        keywords.add('upbeat');
        keywords.add('light');
        keywords.add('background');
        keywords.add('instrumental');
        keywords.add('positive');
        break;
      case 'dramatic':
        keywords.add('dramatic');
        keywords.add('cinematic');
        keywords.add('background');
        keywords.add('instrumental');
        keywords.add('epic');
        break;
    }

    return Array.from(keywords);
  }

  private getMusicKeywords(tone: ReelTone, mood: string): string[] {
    const keywords = new Set<string>();

    // Add mood-based keywords first (higher priority)
    if (mood) {
      keywords.add(mood.toLowerCase());
      
      // Add related mood keywords
      switch (mood.toLowerCase()) {
        case 'happy':
        case 'upbeat':
          keywords.add('uplifting');
          keywords.add('positive');
          keywords.add('cheerful');
          break;
        case 'serious':
        case 'professional':
          keywords.add('corporate');
          keywords.add('business');
          keywords.add('focused');
          break;
        case 'energetic':
        case 'dynamic':
          keywords.add('powerful');
          keywords.add('motivational');
          keywords.add('intense');
          break;
        case 'calm':
        case 'peaceful':
          keywords.add('ambient');
          keywords.add('relaxing');
          keywords.add('gentle');
          break;
        case 'dramatic':
        case 'intense':
          keywords.add('epic');
          keywords.add('cinematic');
          keywords.add('powerful');
          break;
        case 'inspirational':
          keywords.add('uplifting');
          keywords.add('motivational');
          keywords.add('inspiring');
          break;
      }
    }

    // Add tone-based keywords
    switch (tone) {
      case 'professional':
        keywords.add('corporate');
        keywords.add('business');
        break;
      case 'casual':
        keywords.add('upbeat');
        keywords.add('light');
        break;
      case 'dramatic':
        keywords.add('dramatic');
        keywords.add('intense');
        break;
    }

    // Always add these base keywords
    keywords.add('background');
    keywords.add('instrumental');
    keywords.add('music');

    return Array.from(keywords);
  }

  private getGenericMusicKeywords(tone: ReelTone): string[] {
    const baseKeywords = ['background', 'instrumental'];
    
    switch (tone) {
      case 'professional':
        return [...baseKeywords, 'corporate', 'ambient'];
      case 'casual':
        return [...baseKeywords, 'upbeat', 'light'];
      case 'dramatic':
        return [...baseKeywords, 'cinematic', 'epic'];
      default:
        return baseKeywords;
    }
  }
}