import OpenAI from 'openai';
import * as fs from 'fs';
import { ReelTone } from '../types';
import config from '../config';

export interface Caption {
  start: number;
  end: number;
  text: string;
}

export class WhisperService {
  private readonly openai: OpenAI;

  constructor() {
    this.openai = new OpenAI({
      apiKey: config.openai.apiKey
    });
  }

  async generateCaptions(audioPath: string, tone: ReelTone): Promise<string> {
    try {
      // First, transcribe the audio with timestamps
      const transcription = await this.transcribeAudio(audioPath);
      
      // Generate SRT file with styled captions
      const srtContent = this.generateStyledSRT(transcription, tone);
      
      // Save to temporary file
      const srtPath = audioPath.replace('.mp3', '.srt');
      fs.writeFileSync(srtPath, srtContent);
      
      return srtPath;
    } catch (error: any) {
      console.error('Error generating captions:', error);
      throw new Error(`Failed to generate captions: ${error.message}`);
    }
  }

  private async transcribeAudio(audioPath: string): Promise<Caption[]> {
    const transcription = await this.openai.audio.transcriptions.create({
      file: fs.createReadStream(audioPath),
      model: 'whisper-1',
      response_format: 'verbose_json',
      timestamp_granularities: ['segment']
    });

    return (transcription as any).segments.map((segment: any) => ({
      start: segment.start,
      end: segment.end,
      text: segment.text.trim()
    }));
  }

  private generateStyledSRT(captions: Caption[], tone: ReelTone): string {
    let srtContent = '';
    let index = 1;

    for (const caption of captions) {
      const startTime = this.formatTimestamp(caption.start);
      const endTime = this.formatTimestamp(caption.end);
      const styledText = this.applyCaptionStyle(caption.text, tone);

      srtContent += `${index}\n`;
      srtContent += `${startTime} --> ${endTime}\n`;
      srtContent += `${styledText}\n\n`;
      
      index++;
    }

    return srtContent;
  }

  private formatTimestamp(seconds: number): string {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = Math.floor(seconds % 60);
    const ms = Math.floor((seconds % 1) * 1000);

    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')},${ms.toString().padStart(3, '0')}`;
  }

  private applyCaptionStyle(text: string, tone: ReelTone): string {
    switch (tone) {
      case 'professional':
        // Clean, minimal style with consistent formatting
        return `<font face="Arial">${text}</font>`;
        
      case 'casual':
        // More dynamic, friendly style with mixed case
        return `<font face="Comic Sans MS" color="#FFFFFF">${text}</font>`;
        
      case 'dramatic':
        // Bold, impactful style with dramatic formatting
        return `<font face="Impact" size="24"><b>${text.toUpperCase()}</b></font>`;
        
      default:
        return text;
    }
  }
} 