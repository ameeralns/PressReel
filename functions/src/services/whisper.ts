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
    const { verticalPosition, isBold, italic } = this.getStyleSettingsForTone();

    // ASS header with script info and randomized styles
    const header = `[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,${selectedFont},${selectedFontSize},${primaryColor},&H000000FF,${outlineColor},&H80000000,${isBold},${italic},0,0,100,100,0,0,1,${selectedOutline},0,8,10,10,${verticalPosition},1

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
        return [
          'Helvetica Neue',
          'Arial Black',
          'Montserrat',
          'Roboto Condensed'
        ];
      case 'professional':
        return [
          'Helvetica',
          'Arial',
          'Roboto',
          'Open Sans',
          'Source Sans Pro'
        ];
      case 'casual':
        return [
          'Helvetica',
          'Verdana',
          'Trebuchet MS',
          'Avenir',
          'Montserrat'
        ];
      default:
        return ['Helvetica', 'Arial', 'Roboto'];
    }
  }

  private getFontSizesForTone(): number[] {
    switch (this.tone) {
      case 'dramatic':
        return [58, 62, 64];
      case 'professional':
        return [52, 54, 56];
      case 'casual':
        return [54, 56, 58];
      default:
        return [54, 56];
    }
  }

  private getOutlineThicknessesForTone(): number[] {
    switch (this.tone) {
      case 'dramatic':
        return [2.5, 3];
      case 'professional':
        return [2, 2.2];
      case 'casual':
        return [2.2, 2.5];
      default:
        return [2.2];
    }
  }

  private getColorsForTone(): { primaryColor: string; outlineColor: string; highlightColor: string } {
    const colors = {
      dramatic: [
        { primaryColor: '&H00FFFFFF', outlineColor: '&H00000000', highlightColor: '&H00FFF000' }, // White/Black/Gold
        { primaryColor: '&H00FFFFFF', outlineColor: '&H00000000', highlightColor: '&H00FF0000' }  // White/Black/Red
      ],
      professional: [
        { primaryColor: '&H00FFFFFF', outlineColor: '&H00000000', highlightColor: '&H00FFF000' }, // White/Black/Gold
        { primaryColor: '&H00FFFFFF', outlineColor: '&H00000000', highlightColor: '&H00FF0000' }  // White/Black/Red
      ],
      casual: [
        { primaryColor: '&H00FFFFFF', outlineColor: '&H00000000', highlightColor: '&H00FFF000' }, // White/Black/Gold
        { primaryColor: '&H00FFFFFF', outlineColor: '&H00000000', highlightColor: '&H00FF0000' }  // White/Black/Red
      ]
    };

    const toneColors = colors[this.tone] || colors.professional;
    return toneColors[Math.floor(Math.random() * toneColors.length)];
  }

  private getStyleSettingsForTone(): { verticalPosition: number; isBold: number; italic: number; effects: string[] } {
    const baseEffects = [
      '\\fad(150,150)', // Subtle fade in/out
      '\\blur1\\t(0,150,\\blur0)', // Subtle blur transition
      '\\fscx105\\fscy105\\t(0,150,\\fscx100\\fscy100)' // Subtle scale transition
    ];

    switch (this.tone) {
      case 'dramatic':
        return {
          verticalPosition: 920,
          isBold: 1,
          italic: 0,
          effects: [
            '\\fad(200,200)',
            '\\blur2\\t(0,200,\\blur0)',
            '\\fscx110\\fscy110\\t(0,200,\\fscx100\\fscy100)'
          ]
        };
      case 'professional':
        return {
          verticalPosition: 960,
          isBold: 0,
          italic: 0,
          effects: [
            '\\fad(150,150)',
            '\\blur0.5\\t(0,100,\\blur0)'
          ]
        };
      case 'casual':
        return {
          verticalPosition: 940,
          isBold: Math.random() > 0.7 ? 1 : 0,
          italic: 0,
          effects: baseEffects
        };
      default:
        return {
          verticalPosition: 960,
          isBold: 0,
          italic: 0,
          effects: ['\\fad(150,150)']
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
        return currentGroup.length >= 2 || isEndOfSentence || isLastWord; // Show two words at a time minimum
      case 'casual':
        return currentGroup.length >= 3 || isEndOfSentence || isBreathPause || isLastWord;
      case 'professional':
        return currentGroup.length >= 3 || isEndOfSentence || (isBreathPause && currentGroup.length >= 2) || isLastWord;
      default:
        return currentGroup.length >= 3 || isEndOfSentence || isLastWord;
    }
  }

  private generateTextWithEffects(currentGroup: WhisperWord[], highlightColor: string): string {
    const styleSettings = this.getStyleSettingsForTone();
    const effect = styleSettings.effects[Math.floor(Math.random() * styleSettings.effects.length)];
    
    const words = currentGroup.map(w => {
      const duration = Math.round((w.end - w.start) * 100);
      return `{\\k${duration}\\c${highlightColor}}${w.word}`;
    }).join(' ');

    return `{${effect}}${words}`;
  }
} 