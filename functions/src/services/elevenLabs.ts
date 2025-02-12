import axios from 'axios';
import { ReelTone } from '../types';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import config from '../config';

interface Voice {
  voice_id: string;
  name: string;
  category: string;
  preview_url: string;
}

export class ElevenLabsService {
  private readonly apiKey: string;
  private readonly baseURL = 'https://api.elevenlabs.io/v1';

  constructor() {
    this.apiKey = config.elevenLabs.apiKey;
    
    // Validate API key format and presence
    if (!this.apiKey) {
      throw new Error('ElevenLabs API key is missing');
    }
    if (!this.apiKey.startsWith('sk_')) {
      throw new Error('Invalid ElevenLabs API key format');
    }
  }

  private async validateApiKey(): Promise<boolean> {
    try {
      const response = await axios.get(`${this.baseURL}/voices`, {
        headers: {
          'xi-api-key': this.apiKey
        }
      });
      return response.status === 200;
    } catch (error: any) {
      if (error.response?.status === 401) {
        throw new Error('ElevenLabs API key is invalid or expired');
      }
      throw error;
    }
  }

  private cleanScript(script: string): string {
    // Remove section headers in brackets and their labels
    const cleanedScript = script
      .replace(/\[.*?\]\s*/g, '') // Remove [HOOK], [KEY POINT 1], etc.
      .replace(/^\s*[\r\n]/gm, '') // Remove empty lines
      .trim();
    
    console.log('Cleaned script:', cleanedScript);
    return cleanedScript;
  }

  private getVoiceSettings(tone: ReelTone): {
    stability: number;
    similarity_boost: number;
    style: number;
    use_speaker_boost: boolean;
  } {
    // Adjust voice parameters based on tone
    switch (tone) {
      case 'professional':
        return {
          stability: 0.85, // More stable for professional tone
          similarity_boost: 0.75,
          style: 0.15, // Subtle style variation
          use_speaker_boost: true
        };
      case 'casual':
        return {
          stability: 0.65, // More natural variations
          similarity_boost: 0.7,
          style: 0.35, // More style variation for casual tone
          use_speaker_boost: true
        };
      case 'dramatic':
        return {
          stability: 0.55, // More variations for dramatic effect
          similarity_boost: 0.85,
          style: 0.65, // Strong style for dramatic impact
          use_speaker_boost: true
        };
      default:
        return {
          stability: 0.75,
          similarity_boost: 0.75,
          style: 0.25,
          use_speaker_boost: true
        };
    }
  }

  async getVoices(): Promise<Voice[]> {
    try {
      console.log('ElevenLabs Service: Starting to fetch voices');
      console.log('Using API Key:', this.apiKey ? 'Present' : 'Missing');
      console.log('Request URL:', `${this.baseURL}/voices`);

      const response = await axios.get(`${this.baseURL}/voices`, {
        headers: {
          'xi-api-key': this.apiKey
        }
      });

      console.log('ElevenLabs API Response Status:', response.status);
      console.log('ElevenLabs API Response Data:', JSON.stringify(response.data, null, 2));

      if (!response.data.voices) {
        console.error('No voices array in response:', response.data);
        return [];
      }

      const mappedVoices = response.data.voices.map((voice: any) => ({
        voice_id: voice.voice_id,
        name: voice.name,
        category: voice.labels?.accent || voice.labels?.description || 'General',
        preview_url: voice.preview_url
      }));

      console.log('Mapped voices:', JSON.stringify(mappedVoices, null, 2));
      return mappedVoices;
    } catch (error: any) {
      console.error('Error in ElevenLabs getVoices:', error);
      if (error.response) {
        console.error('Error response:', {
          status: error.response.status,
          data: error.response.data,
          headers: error.response.headers
        });
      }
      throw new Error(`Failed to fetch voices: ${error.message}`);
    }
  }

  async generateVoiceover(script: string, voiceId: string, tone: ReelTone): Promise<string> {
    try {
      // Validate API key before proceeding
      await this.validateApiKey();

      // Clean the script first
      const cleanedScript = this.cleanScript(script);
      console.log('Original script:', script);
      console.log('Cleaned script:', cleanedScript);

      // Create temp file path
      const tempDir = os.tmpdir();
      const outputPath = path.join(tempDir, `voiceover-${Date.now()}.mp3`);

      // Get voice settings based on tone
      const voiceSettings = this.getVoiceSettings(tone);
      console.log('Voice settings for tone:', tone, voiceSettings);

      const response = await axios({
        method: 'post',
        url: `${this.baseURL}/text-to-speech/${voiceId}`,
        headers: {
          'Accept': 'audio/mpeg',
          'xi-api-key': this.apiKey,
          'Content-Type': 'application/json',
        },
        data: {
          text: cleanedScript,
          model_id: 'eleven_multilingual_v2',
          voice_settings: voiceSettings
        },
        responseType: 'stream'
      });

      // Save the audio stream to temp file
      const writer = fs.createWriteStream(outputPath);
      response.data.pipe(writer);

      return new Promise((resolve, reject) => {
        writer.on('finish', () => resolve(outputPath));
        writer.on('error', reject);
      });
    } catch (error: any) {
      console.error('Error generating voiceover:', error);
      if (error.response?.status === 401) {
        throw new Error('ElevenLabs API key is invalid or expired. Please check your API key configuration.');
      }
      throw new Error(`Failed to generate voiceover: ${error.message}`);
    }
  }
} 