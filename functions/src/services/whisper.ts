import fs from 'fs';
import { TempFileManager } from '../utils';
import { ReelTone } from '../types';
import OpenAI from 'openai';
import config from '../config';

interface WhisperWord {
  word: string;
  start: number;
  end: number;
}

interface WhisperSegment {
  text: string;
  start: number;
  end: number;
  words: WhisperWord[];
}

export class WhisperService {
  private readonly tempFileManager: TempFileManager;
  private readonly openai: OpenAI;
  private readonly tone: ReelTone;

  constructor(tone: ReelTone) {
    this.tempFileManager = TempFileManager.getInstance();
    this.openai = new OpenAI({
      apiKey: config.openai.apiKey
    });
    this.tone = tone;
    console.log(`Initializing WhisperService with tone: ${tone}`);
  }

  async generateCaptions(voiceoverPath: string): Promise<string> {
    try {
      // Validate input file exists
      if (!fs.existsSync(voiceoverPath)) {
        throw new Error(`Audio file not found at path: ${voiceoverPath}`);
      }

      // Create output path for ASS
      const assOutputPath = this.tempFileManager.createTempFilePath('captions', '.ass');

      console.log('Transcribing audio with Whisper API...', {
        voiceoverPath
      });

      // Create a read stream for the audio file
      const audioStream = fs.createReadStream(voiceoverPath);

      // Get transcription with word timestamps
      const transcription = await this.openai.audio.transcriptions.create({
        file: audioStream,
        model: 'whisper-1',
        language: 'en',
        response_format: 'verbose_json'
      });

      console.log('Raw Whisper response:', JSON.stringify(transcription, null, 2));

      // Parse the response into our segment format
      const segments = this.parseWhisperResponse(transcription);
      
      // Generate ASS content with word-level highlighting
      const assContent = this.generateWordLevelASS(segments);
      
      // Write ASS file
      await fs.promises.writeFile(assOutputPath, assContent, 'utf-8');
      
      console.log('Generated word-level captions:', assOutputPath);

      return assOutputPath;
    } catch (error) {
      console.error('Error generating captions:', error);
      throw error;
    }
  }

  private parseWhisperResponse(response: any): WhisperSegment[] {
    try {
      console.log('Parsing response:', response);

      // Handle the actual Whisper API response format
      if (!response || typeof response !== 'object') {
        throw new Error('Invalid response format');
      }

      // The response should have a segments array
      if (!response.segments || !Array.isArray(response.segments)) {
        console.log('No segments array found in response');
        // If no segments, try to create one from the full text
        if (response.text) {
          return [{
            text: response.text,
            start: 0,
            end: response.duration || 0,
            words: []
          }];
        }
        throw new Error('No segments or text found in response');
      }

      return response.segments.map((segment: any, index: number) => {
        console.log(`Processing segment ${index}:`, segment);

        // Extract the required fields with validation
        const text = segment.text?.trim();
        const start = Number(segment.start);
        const end = Number(segment.end);

        if (!text || isNaN(start) || isNaN(end)) {
          console.log('Invalid segment data:', { text, start, end });
          throw new Error(`Invalid segment format at index ${index}`);
        }

        // Create artificial word timestamps if not provided
        const words = this.createWordTimestamps(text, start, end);

        return {
          text,
          start,
          end,
          words
        };
      });
    } catch (error) {
      console.error('Error parsing Whisper API response:', error);
      throw error;
    }
  }

  private createWordTimestamps(text: string, start: number, end: number): WhisperWord[] {
    // Split text into words
    const words = text.split(/\s+/);
    const duration = end - start;
    const wordDuration = duration / words.length;

    return words.map((word, index) => {
      const wordStart = start + (index * wordDuration);
      const wordEnd = wordStart + wordDuration;
      return {
        word: word.trim(),
        start: wordStart,
        end: wordEnd
      };
    });
  }

  private generateWordLevelASS(segments: WhisperSegment[]): string {
    // Define style variations based on tone
    const fonts = this.getFontsForTone();
    const fontSizes = this.getFontSizesForTone();
    const outlineThicknesses = this.getOutlineThicknessesForTone();
    
    // Randomly select styles
    const selectedFont = fonts[Math.floor(Math.random() * fonts.length)];
    const selectedFontSize = fontSizes[Math.floor(Math.random() * fontSizes.length)];
    const selectedOutline = outlineThicknesses[Math.floor(Math.random() * outlineThicknesses.length)];
    
    // Get colors based on tone
    const { primaryColor, outlineColor, highlightColor } = this.getColorsForTone();
    
    // Set vertical position and style based on tone
    const { verticalPosition, isBold } = this.getStyleSettingsForTone();

    // ASS header with script info and randomized styles
    const header = `[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,${selectedFont},${selectedFontSize},${primaryColor},&H000000FF,${outlineColor},&H80000000,${isBold},0,0,0,100,100,0,0,1,${selectedOutline},0,8,10,10,${verticalPosition},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n`;

    let events = '';

    const formatTime = (seconds: number): string => {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = Math.floor(seconds % 60);
        const centisecs = Math.floor((seconds % 1) * 100);
        return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}.${String(centisecs).padStart(2, '0')}`;
    };

    // Process segments based on tone
    segments.forEach((segment) => {
        const words = segment.words;
        let currentGroup: WhisperWord[] = [];
        
        for (let i = 0; i < words.length; i++) {
            const word = words[i];
            currentGroup.push(word);
            
            const isEndOfSentence = !!word.word.match(/[.!?]$/);
            const isBreathPause = !!word.word.match(/[,;:]$/);
            const isLastWord = i === words.length - 1;

            // Get grouping logic based on tone
            const shouldWriteGroup = this.shouldWriteGroup(currentGroup, isEndOfSentence, isBreathPause, isLastWord);
            
            if (shouldWriteGroup) {
                const groupStart = currentGroup[0].start;
                const groupEnd = currentGroup[currentGroup.length - 1].end;
                
                // Generate text with appropriate effects for the tone
                const text = this.generateTextWithEffects(currentGroup, highlightColor);
                
                events += `Dialogue: 0,${formatTime(groupStart)},${formatTime(groupEnd)},Default,,0,0,0,,${text}\\N\n`;
                
                currentGroup = [];
            }
        }
    });

    return header + events;
  }

  private getFontsForTone(): string[] {
    switch (this.tone) {
      case 'dramatic':
        return ['Impact', 'Arial Black', 'Helvetica Neue'];
      case 'professional':
        return ['Arial', 'Helvetica', 'Roboto'];
      case 'casual':
        return ['Verdana', 'Trebuchet MS', 'Helvetica Rounded'];
      default:
        return ['Arial', 'Helvetica'];
    }
  }

  private getFontSizesForTone(): number[] {
    switch (this.tone) {
      case 'dramatic':
        return [64, 68, 72];
      case 'professional':
        return [54, 58, 62];
      case 'casual':
        return [58, 62, 66];
      default:
        return [60, 64];
    }
  }

  private getOutlineThicknessesForTone(): number[] {
    switch (this.tone) {
      case 'dramatic':
        return [3, 3.5, 4];
      case 'professional':
        return [2, 2.5];
      case 'casual':
        return [2.5, 3];
      default:
        return [2.5];
    }
  }

  private getColorsForTone(): { primaryColor: string; outlineColor: string; highlightColor: string } {
    switch (this.tone) {
      case 'dramatic':
        return {
          primaryColor: '&H00FFFFFF', // White
          outlineColor: '&H00000000', // Black
          highlightColor: '&H0000FFFF' // Bright cyan
        };
      case 'professional':
        return {
          primaryColor: '&H00F0F0F0', // Light gray
          outlineColor: '&H00222222', // Dark gray
          highlightColor: '&H00FFF000' // Yellow
        };
      case 'casual':
        return {
          primaryColor: '&H00FFE5CC', // Light peach
          outlineColor: '&H00003300', // Dark green
          highlightColor: '&H0000FF00' // Green
        };
      default:
        return {
          primaryColor: '&H00FFFFFF',
          outlineColor: '&H00000000',
          highlightColor: '&H00FFF000'
        };
    }
  }

  private getStyleSettingsForTone(): { verticalPosition: number; isBold: number } {
    switch (this.tone) {
      case 'dramatic':
        return {
          verticalPosition: 900, // Higher up for dramatic effect
          isBold: 1
        };
      case 'professional':
        return {
          verticalPosition: 960, // Standard position
          isBold: 0
        };
      case 'casual':
        return {
          verticalPosition: Math.floor(Math.random() * 200) + 800, // Random position
          isBold: Math.random() > 0.5 ? 1 : 0
        };
      default:
        return {
          verticalPosition: 960,
          isBold: 0
        };
    }
  }

  private shouldWriteGroup(
    currentGroup: WhisperWord[],
    isEndOfSentence: boolean,
    isBreathPause: boolean,
    isLastWord: boolean
  ): boolean {
    switch (this.tone) {
      case 'dramatic':
        return true; // Show one word at a time
      case 'casual':
        return currentGroup.length >= 3 || isEndOfSentence || isBreathPause || isLastWord;
      case 'professional':
        return currentGroup.length >= 3 || isEndOfSentence || (isBreathPause && currentGroup.length >= 2) || isLastWord;
      default:
        return currentGroup.length >= 3 || isEndOfSentence || isLastWord;
    }
  }

  private generateTextWithEffects(currentGroup: WhisperWord[], highlightColor: string): string {
    if (this.tone === 'dramatic') {
      const dramaticEffects = [
        '\\t(0,100,\\fscx120\\fscy120)\\t(100,200,\\fscx100\\fscy100)', // Quick punch in
        '\\t(0,150,\\frz20)\\t(150,300,\\frz0)', // Rotate in
        '\\t(0,100,\\fscx120\\fscy80)\\t(100,200,\\fscx100\\fscy100)', // Horizontal stretch
        '\\t(0,150,\\blur5)\\t(150,300,\\blur0)', // Blur in
        '\\fad(100,100)' // Quick fade
      ];
      const effect = dramaticEffects[Math.floor(Math.random() * dramaticEffects.length)];
      const word = currentGroup[0]; // For dramatic, we only have one word
      const duration = Math.round((word.end - word.start) * 100);
      return `{\\k${duration}\\c${highlightColor}${effect}}${word.word}`;
    } else {
      return currentGroup.map(w => {
        const duration = Math.round((w.end - w.start) * 100);
        return `{\\k${duration}\\c${highlightColor}}${w.word}`;
      }).join(' ');
    }
  }
} 