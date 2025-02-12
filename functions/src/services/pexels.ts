import { VideoScene, SceneMedia, PixabayMedia } from '../types';
import config from '../config';
import os from 'os';
import path from 'path';
import fs from 'fs';
import axios from 'axios';

interface PexelsVideo {
  id: number;
  width: number;
  height: number;
  duration: number;
  url: string;
  video_files: {
    id: number;
    quality: string;
    file_type: string;
    width: number;
    height: number;
    link: string;
  }[];
}

interface PexelsImage {
  id: number;
  width: number;
  height: number;
  url: string;
  src: {
    original: string;
    large2x: string;
    large: string;
    medium: string;
    small: string;
    portrait: string;
    landscape: string;
    tiny: string;
  };
}

type VisualType = 'b-roll' | 'static' | 'talking' | 'overlay';
type Mood = 'dramatic' | 'professional' | 'urgent' | 'reflective' | 'inspirational';

interface ScriptContext {
  mainTopic: string;
  domain: string;
  setting: string;
}

export class PexelsService {
  private readonly apiKey: string;
  private readonly videoBaseURL = 'https://api.pexels.com/videos';
  private readonly imageBaseURL = 'https://api.pexels.com/v1';
  private readonly tempDir: string;
  private readonly headers: { [key: string]: string };
  private usedVideos = new Map<number, { timestamp: number, query: string }>();
  private readonly VIDEO_REUSE_TIMEOUT = 1000 * 60 * 5; // 5 minutes

  constructor() {
    this.apiKey = config.pexels.apiKey;
    this.tempDir = os.tmpdir();
    this.headers = {
      'Authorization': this.apiKey,
      'Content-Type': 'application/json'
    };
  }

  async fetchMediaForScene(scene: VideoScene): Promise<SceneMedia> {
    try {
      console.log('Starting Pexels media fetch for scene:', {
        description: scene.description,
        duration: scene.duration,
        visualType: scene.visualType
      });

      let primaryMedia: PixabayMedia[] = [];
      let searchAttempts = 0;
      const maxAttempts = 5;

      // Generate search strategies with broader, more adaptable keywords
      const searchStrategies = this.generateSearchStrategies(scene);

      for (const strategy of searchStrategies) {
        if (searchAttempts >= maxAttempts) break;
        searchAttempts++;

        try {
          console.log(`Pexels search attempt ${searchAttempts} with strategy:`, strategy);
          primaryMedia = await this.fetchPrimaryMedia(
            scene.visualType,
            strategy,
            scene.duration
          );

          if (primaryMedia.length > 0) {
            console.log(`Found media using strategy:`, strategy);
            break;
          }
        } catch (error) {
          console.log(`Search attempt ${searchAttempts} failed with strategy:`, strategy, error);
        }
      }

      // Fallback search if no results found
      if (primaryMedia.length === 0) {
        console.log('Attempting fallback search...');
        try {
          const fallbackStrategy = this.generateFallbackStrategy(scene);
          primaryMedia = await this.fetchPrimaryMedia(
            scene.visualType,
            fallbackStrategy,
            scene.duration
          );
        } catch (error) {
          console.log('Fallback search failed:', error);
        }
      }

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
      console.error('Error fetching media from Pexels:', error);
      throw new Error(`Failed to fetch media: ${error.message}`);
    }
  }

  private extractScriptContext(scene: VideoScene): ScriptContext {
    const governmentTerms = ['federal', 'government', 'white house', 'office', 'administration'];
    const businessTerms = ['corporate', 'business', 'professional', 'workplace'];
    
    const description = scene.description.toLowerCase();
    const primaryKeywords = scene.primaryKeywords.map(k => k.toLowerCase());
    const secondaryKeywords = scene.secondaryKeywords.map(k => k.toLowerCase());
    
    // Determine the main topic and domain
    const isGovernment = [...governmentTerms, 'federal', 'government']
      .some(term => description.includes(term) || 
            primaryKeywords.some(k => k.includes(term)) ||
            secondaryKeywords.some(k => k.includes(term)));

    const isBusiness = !isGovernment && businessTerms
      .some(term => description.includes(term) || 
            primaryKeywords.some(k => k.includes(term)) ||
            secondaryKeywords.some(k => k.includes(term)));

    return {
      mainTopic: isGovernment ? 'government' : (isBusiness ? 'business' : 'professional'),
      domain: isGovernment ? 'federal workplace' : (isBusiness ? 'corporate office' : 'office'),
      setting: isGovernment ? 'government building' : (isBusiness ? 'corporate building' : 'office building')
    };
  }

  private extractConcepts(description: string): string[] {
    const stopWords = new Set(['the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by']);
    const words = description.toLowerCase()
      .replace(/[^\w\s]/g, '')
      .split(' ')
      .filter(word => !stopWords.has(word));
    
    const conceptGroups: { [key: string]: string[] } = {
      government: [
        'federal', 'government', 'administration', 'white', 'house', 'agency', 'department',
        'official', 'public', 'service', 'policy'
      ],
      business: [
        'office', 'corporate', 'business', 'professional', 'work', 'working', 'workplace',
        'desk', 'meeting', 'conference'
      ],
      people: [
        'employee', 'worker', 'staff', 'person', 'people', 'group', 'team', 'executive',
        'manager', 'professional', 'colleague'
      ],
      action: [
        'leaving', 'exiting', 'walking', 'working', 'meeting', 'discussing', 'presenting',
        'typing', 'moving', 'standing', 'sitting'
      ],
      environment: [
        'building', 'office', 'room', 'interior', 'exterior', 'window', 'door', 'desk',
        'workspace', 'hallway', 'lobby'
      ],
      time: ['morning', 'day', 'evening', 'deadline', 'time', 'period', 'moment'],
      status: ['resignation', 'exit', 'change', 'transition', 'shift', 'movement']
    };

    const concepts = new Set<string>();
    words.forEach(word => {
      for (const [concept, terms] of Object.entries(conceptGroups)) {
        if (terms.includes(word)) {
          concepts.add(concept);
          concepts.add(word);
        }
      }
    });

    return Array.from(concepts);
  }

  private getBroadConceptualTerms(concepts: string[], mood: string): string[] {
    const terms = [...concepts];
    
    // Add context-preserving terms
    const contextualTerms = [
      'office environment',
      'workplace',
      'professional setting',
      'business district',
      'corporate building'
    ];
    
    terms.push(...contextualTerms);
    
    const moodModifiers: Record<Mood, string[]> = {
      dramatic: ['serious', 'impactful', 'significant'],
      professional: ['formal', 'business', 'corporate'],
      urgent: ['pressing', 'immediate', 'critical'],
      reflective: ['thoughtful', 'contemplative', 'considered'],
      inspirational: ['motivational', 'encouraging', 'positive']
    };

    if (moodModifiers[mood as Mood]) {
      terms.push(...moodModifiers[mood as Mood]);
    }

    return terms;
  }

  private getVisualStyleTerms(visualType: string, mood: string): string[] {
    const styleTerms: Record<VisualType, string[]> = {
      'b-roll': [
        'professional footage',
        'office environment',
        'corporate setting',
        'business district',
        'workplace scene'
      ],
      'static': [
        'office interior',
        'workplace setting',
        'professional environment',
        'corporate space'
      ],
      'talking': [
        'professional person',
        'office worker',
        'business person',
        'corporate employee'
      ],
      'overlay': [
        'office background',
        'corporate texture',
        'business pattern',
        'professional overlay'
      ]
    };

    return [
      ...(styleTerms[visualType as VisualType] || []),
      'professional',
      'business setting',
      'high quality'
    ];
  }

  private getActionTerms(description: string, visualType: string): string[] {
    const actionWords = description.toLowerCase()
      .match(/\b(walking|running|typing|working|standing|sitting|moving|looking)\b/g) || [];
    
    const genericActions: Record<VisualType, string[]> = {
      'b-roll': ['motion', 'movement', 'activity'],
      'static': ['stillness', 'presence'],
      'talking': ['communication', 'interaction'],
      'overlay': ['floating', 'overlaying']
    };

    return [
      ...actionWords,
      ...(genericActions[visualType as VisualType] || [])
    ];
  }

  private getMoodTerms(mood: string, visualType: string): string[] {
    const moodTerms: Record<Mood, string[]> = {
      dramatic: ['intense', 'powerful', 'impactful'],
      professional: ['formal', 'organized', 'structured'],
      urgent: ['dynamic', 'energetic', 'quick'],
      reflective: ['thoughtful', 'contemplative', 'serene'],
      inspirational: ['uplifting', 'motivational', 'positive']
    };

    return [
      ...(moodTerms[mood as Mood] || []),
      visualType === 'b-roll' ? 'establishing' : '',
      'atmosphere',
      'mood'
    ].filter(term => term);
  }

  private generateSearchStrategies(scene: VideoScene): string[][] {
    const strategies: string[][] = [];
    const context = this.extractScriptContext(scene);
    
    // Extract key concepts from the scene description
    const concepts = this.extractConcepts(scene.description);
    
    // Strategy 1: Context-aware conceptual terms
    const contextualTerms = [
      context.domain,
      context.setting,
      ...this.getBroadConceptualTerms(concepts, scene.mood)
    ];
    strategies.push(contextualTerms);
    
    // Strategy 2: Professional setting with visual style
    const professionalTerms = [
      'professional',
      'office',
      'business',
      context.mainTopic,
      ...this.getVisualStyleTerms(scene.visualType, scene.mood)
    ];
    strategies.push(professionalTerms);
    
    // Strategy 3: Action and environment
    const actionTerms = [
      ...this.getActionTerms(scene.description, scene.visualType),
      context.setting,
      'workplace'
    ];
    strategies.push(actionTerms);
    
    // Strategy 4: Mood and atmosphere in professional context
    const moodTerms = [
      ...this.getMoodTerms(scene.mood, scene.visualType),
      'office',
      'professional',
      context.domain
    ];
    strategies.push(moodTerms);
    
    // Filter out empty arrays and deduplicate terms
    return strategies
      .filter(strategy => strategy.length > 0)
      .map(strategy => Array.from(new Set(strategy)));
  }

  private generateFallbackStrategy(scene: VideoScene): string[] {
    const context = this.extractScriptContext(scene);
    const fallbackTerms = new Set<string>();
    
    // Add context-preserving terms
    fallbackTerms.add(context.domain);
    fallbackTerms.add('office');
    fallbackTerms.add('professional');
    fallbackTerms.add('business');
    
    // Add visual type related terms
    if (scene.visualType === 'b-roll') {
      fallbackTerms.add('office footage');
      fallbackTerms.add('workplace scene');
    } else {
      fallbackTerms.add('office scene');
      fallbackTerms.add('workplace');
    }
    
    // Add mood-based term
    fallbackTerms.add(scene.mood);
    
    return Array.from(fallbackTerms);
  }

  private async fetchPrimaryMedia(
    visualType: string,
    keywords: string[],
    duration: number
  ): Promise<PixabayMedia[]> {
    switch (visualType) {
      case 'b-roll':
      case 'talking':
        const result = await this.searchVideos(keywords, duration);
        // If no results, try with a subset of keywords
        if (result.length === 0 && keywords.length > 2) {
          console.log('Retrying with reduced keywords...');
          return this.searchVideos(keywords.slice(0, 2), duration);
        }
        return result;
      case 'static':
        return this.searchImages(keywords);
      case 'overlay':
        return []; // Overlays handled separately
      default:
        throw new Error(`Unsupported visual type: ${visualType}`);
    }
  }

  private isVideoUsedRecently(videoId: number, currentQuery: string): boolean {
    const usedVideo = this.usedVideos.get(videoId);
    if (!usedVideo) return false;

    const now = Date.now();
    // Allow reuse if it's been long enough AND it's for a completely different query
    if (now - usedVideo.timestamp > this.VIDEO_REUSE_TIMEOUT && 
        !this.areQueriesSimilar(currentQuery, usedVideo.query)) {
      this.usedVideos.delete(videoId);
      return false;
    }
    return true;
  }

  private areQueriesSimilar(query1: string, query2: string): boolean {
    const words1 = new Set(query1.toLowerCase().split(' '));
    const words2 = new Set(query2.toLowerCase().split(' '));
    const intersection = new Set([...words1].filter(x => words2.has(x)));
    const union = new Set([...words1, ...words2]);
    return intersection.size / union.size > 0.3; // If more than 30% words match
  }

  private cleanupUsedVideos(): void {
    const now = Date.now();
    for (const [id, data] of this.usedVideos.entries()) {
      if (now - data.timestamp > this.VIDEO_REUSE_TIMEOUT) {
        this.usedVideos.delete(id);
      }
    }
  }

  private async searchVideos(
    keywords: string[],
    targetDuration: number
  ): Promise<PixabayMedia[]> {
    this.cleanupUsedVideos(); // Cleanup expired entries
    const query = keywords.join(' ');
    const params = new URLSearchParams({
      query,
      orientation: 'portrait',
      size: 'large',
      per_page: '30' // Increased to get more options
    });

    try {
      const response = await axios.get(
        `${this.videoBaseURL}/search?${params.toString()}`,
        { headers: this.headers }
      );

      if (!response.data.videos?.length) {
        return [];
      }

      // Filter and sort videos by duration and quality
      const filteredVideos = response.data.videos
        .filter((video: PexelsVideo) => {
          // Skip recently used videos, but don't retry if no matches
          if (this.isVideoUsedRecently(video.id, query)) {
            return false;
          }

          // Get HD or Full HD video file
          const videoFile = video.video_files.find((file: { quality: string; width: number }) => 
            (file.quality === 'hd' || file.quality === 'sd') && 
            file.width >= 1080
          );
          return videoFile && Math.abs(video.duration - targetDuration) <= 5;
        })
        .sort((a: PexelsVideo, b: PexelsVideo) => {
          // Prioritize vertical videos
          const aIsVertical = a.height > a.width;
          const bIsVertical = b.height > b.width;
          if (aIsVertical !== bIsVertical) {
            return aIsVertical ? -1 : 1;
          }
          // Then sort by duration match
          return Math.abs(a.duration - targetDuration) - Math.abs(b.duration - targetDuration);
        });

      // Take top matches, preferring vertical videos
      const verticalVideos = filteredVideos.filter((v: PexelsVideo) => v.height > v.width);
      const horizontalVideos = filteredVideos.filter((v: PexelsVideo) => v.width >= v.height);
      
      // Prefer vertical videos, but include horizontal if needed
      const topMatches = [
        ...verticalVideos.slice(0, 4),
        ...horizontalVideos.slice(0, 2)
      ].slice(0, 4);

      if (topMatches.length === 0) {
        // If no matches found, return empty array instead of retrying
        console.log('No matching videos found for query:', query);
        return [];
      }

      // Randomly select one from the top matches
      const selectedVideo = topMatches[Math.floor(Math.random() * topMatches.length)];
      
      // Mark this video as used with current timestamp and query
      this.usedVideos.set(selectedVideo.id, { 
        timestamp: Date.now(),
        query
      });
      
      const videoFile = selectedVideo.video_files.find((file: PexelsVideo['video_files'][0]) => 
        (file.quality === 'hd' || file.quality === 'sd') && 
        file.width >= 1080
      );

      if (!videoFile) return [];

      // Log the selection process
      console.log('Video selection:', {
        totalMatches: filteredVideos.length,
        verticalMatches: verticalVideos.length,
        horizontalMatches: horizontalVideos.length,
        topMatchesCount: topMatches.length,
        selectedVideoId: selectedVideo.id,
        isVertical: selectedVideo.height > selectedVideo.width,
        usedVideosCount: this.usedVideos.size,
        duration: selectedVideo.duration,
        targetDuration,
        query
      });

      return [{
        type: 'video',
        url: videoFile.link,
        width: videoFile.width,
        height: videoFile.height,
        isHorizontal: selectedVideo.width > selectedVideo.height
      }];
    } catch (error: any) {
      // Handle rate limiting
      if (error.response?.status === 429) {
        console.log('Rate limit reached, waiting before retrying...');
        // Wait for 1 second before next attempt
        await new Promise(resolve => setTimeout(resolve, 1000));
        return [];
      }
      console.error('Pexels video search error:', error);
      return [];
    }
  }

  private async searchImages(keywords: string[]): Promise<PixabayMedia[]> {
    const query = keywords.join(' ');
    const params = new URLSearchParams({
      query,
      orientation: 'portrait',
      size: 'large',
      per_page: '15'
    });

    try {
      const response = await axios.get(
        `${this.imageBaseURL}/search?${params.toString()}`,
        { headers: this.headers }
      );

      if (!response.data.photos?.length) {
        return [];
      }

      // Get the best quality image that meets our requirements
      const filteredPhotos = response.data.photos
        .filter((photo: PexelsImage) => photo.height >= 1920)
        .slice(0, 1)
        .map((photo: PexelsImage) => ({
          type: 'image' as const,
          url: photo.src.large2x || photo.src.large,
          width: photo.width,
          height: photo.height
        }));

      return filteredPhotos;
    } catch (error) {
      console.error('Pexels image search error:', error);
      return [];
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
        
        // For horizontal videos, create a vertically trimmed version
        let finalPath = localPath;
        if (item.type === 'video' && (item as any).isHorizontal) {
          const trimmedPath = path.join(this.tempDir, `media-${Date.now()}-trimmed.mp4`);
          await this.createVerticalVersion(localPath, trimmedPath);
          finalPath = trimmedPath;
        }
        
        // Validate the downloaded file
        if (await this.validateDownloadedFile(finalPath, item.type, scene)) {
          validatedMedia.push({
            ...item,
            localPath: finalPath
          });
          console.log(`Successfully validated and stored media at: ${finalPath}`);
        }
      } catch (error) {
        console.error(`Failed to download/validate media item:`, error);
      }
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

      return true;
    } catch (error) {
      console.error('File validation failed:', error);
      return false;
    }
  }

  private async createVerticalVersion(inputPath: string, outputPath: string): Promise<void> {
    return new Promise((resolve, reject) => {
      // Use ffmpeg to crop the video to vertical format
      // This takes the center portion of the video and crops it to 9:16 aspect ratio
      const ffmpeg = require('fluent-ffmpeg');
      ffmpeg(inputPath)
        .outputOptions([
          // Crop from center to achieve 9:16 aspect ratio without padding
          '-vf', 'crop=ih*9/16:ih:in_w/2-((ih*9/16)/2):0',
          '-c:v', 'libx264',
          '-preset', 'ultrafast',
          '-crf', '23'
        ])
        .output(outputPath)
        .on('start', (cmd: string) => {
          console.log('Creating vertical version with command:', cmd);
        })
        .on('end', () => {
          console.log('Successfully created vertical version');
          resolve();
        })
        .on('error', (err: Error) => {
          console.error('Error creating vertical version:', err);
          reject(err);
        })
        .run();
    });
  }
} 