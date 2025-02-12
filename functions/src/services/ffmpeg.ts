import ffmpeg from 'fluent-ffmpeg';
import { VideoScene, SceneMedia, ReelTone, EffectConfig, TransitionType } from '../types';
import { TempFileManager } from '../utils';
import fs from 'fs';

export class FFmpegService {
  private readonly tempFileManager: TempFileManager;

  constructor() {
    this.tempFileManager = TempFileManager.getInstance();
    
    // Set up ffmpeg and ffprobe paths
    try {
      const ffmpegPath = require('ffmpeg-static');
      const ffprobePath = require('ffprobe-static').path;
      
      console.log('FFmpeg paths:', {
        ffmpeg: ffmpegPath,
        ffprobe: ffprobePath
      });

      // Set both ffmpeg and ffprobe paths
      ffmpeg.setFfmpegPath(ffmpegPath);
      ffmpeg.setFfprobePath(ffprobePath);
      
      // Verify ffmpeg installation
      this.verifyFfmpegInstallation();
      
      console.log('✅ FFmpeg and FFprobe initialized successfully');
    } catch (error) {
      console.error('Failed to initialize FFmpeg:', error);
      throw new Error('FFmpeg initialization failed');
    }
  }

  private async verifyFfmpegInstallation(): Promise<void> {
    return new Promise((resolve, reject) => {
      // Create a simple command to verify ffmpeg and ffprobe are working
      ffmpeg()
        .input('pipe:0')
        .ffprobe((err, data) => {
          if (err) {
            console.error('FFmpeg verification failed:', err);
            reject(new Error('FFmpeg verification failed'));
            return;
          }
          console.log('FFmpeg verification successful');
          resolve();
        });
    });
  }

  private getEffectFilter(effect: EffectConfig): string {
    switch (effect.type) {
      case 'ken_burns':
        return 'zoompan=z=\'min(zoom+0.002,1.3)\':d=125:x=\'iw/2-(iw/zoom/2)\':y=\'ih/2-(ih/zoom/2)\':s=1080x1920';
      case 'blur_edges':
        return 'split[main][blur];[blur]scale=iw:ih,boxblur=20:20[blurred];[main][blurred]overlay=0:0:eval=init';
      case 'color_boost':
        return 'eq=saturation=1.2:contrast=1.1:brightness=0.05';
      case 'dramatic':
        return 'eq=contrast=1.2:saturation=1.1:brightness=-0.05,unsharp=3:3:1';
      case 'vignette':
        // Add proper vignette effect
        return 'vignette=PI/4';
      default:
        return '';
    }
  }

  private getVerticalFormatFilter(width: number | undefined, height: number | undefined): string {
    if (!width || !height) {
      // Default to scaling if dimensions are unknown
      return 'scale=1080:1920:force_original_aspect_ratio=decrease';
    }
    
    if (width > height) {
      // For horizontal videos/images:
      // 1. Crop from center to 9:16 aspect ratio
      // 2. Scale to 1080x1920
      const cropWidth = Math.round(height * 9/16);
      const xOffset = Math.round((width - cropWidth) / 2);
      return `crop=${cropWidth}:${height}:${xOffset}:0,scale=1080:1920`;
    } else {
      // For vertical videos/images:
      // 1. Crop to 9:16 aspect ratio if needed
      // 2. Scale to 1080x1920
      const targetHeight = Math.round(width * 16/9);
      if (height > targetHeight) {
        // Need to crop height to match 9:16
        const yOffset = Math.round((height - targetHeight) / 2);
        return `crop=${width}:${targetHeight}:0:${yOffset},scale=1080:1920`;
      } else {
        // Already correct aspect ratio or needs padding
        return 'scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2';
      }
    }
  }

  // Process a single scene
  private async processScene(
    mediaPath: string,
    scene: VideoScene,
    index: number,
    type: 'video' | 'image'
  ): Promise<string> {
    console.log(`Processing scene ${index}:`, {
      type,
      duration: scene.duration,
      effect: scene.effect?.type
    });

    // Verify input file exists
    if (!fs.existsSync(mediaPath)) {
      throw new Error(`Input file not found for scene ${index}: ${mediaPath}`);
    }

    const outputPath = this.tempFileManager.createTempFilePath(`scene-${index}`, '.mp4');
    
    return new Promise((resolve, reject) => {
      // First, probe the input to verify it's valid
      ffmpeg.ffprobe(mediaPath, (err, metadata) => {
        if (err) {
          reject(new Error(`Failed to probe input file for scene ${index}: ${err.message}`));
          return;
        }

        let command = ffmpeg(mediaPath)
          .outputOptions([
            '-c:v', 'libx264',
            '-preset', 'ultrafast',
            '-crf', '28',
            '-maxrate', '2500k',
            '-bufsize', '5000k',
            '-pix_fmt', 'yuv420p',
            '-movflags', '+faststart'
          ]);

        // Build filter chain
        let filterParts: string[] = [];
        
        // For images, handle differently than videos
        if (type === 'image') {
          // First scale to vertical format
          filterParts.push(this.getVerticalFormatFilter(metadata.streams[0].width, metadata.streams[0].height));
          
          if (scene.effect?.type === 'ken_burns') {
            filterParts.push(this.getEffectFilter(scene.effect));
          } else if (scene.effect?.type) {
            filterParts.push(this.getEffectFilter(scene.effect));
          }
          
          // For images, we need to generate enough frames for the full duration
          filterParts.push(`loop=loop=-1:size=1:start=0`);
        } else {
          // For videos, apply vertical format and handle looping if needed
          filterParts.push('format=yuv420p');
          filterParts.push(this.getVerticalFormatFilter(metadata.streams[0].width, metadata.streams[0].height));
          
          // If video is shorter than needed duration, loop it
          const videoDuration = metadata.format.duration || 0;
          if (videoDuration < scene.duration) {
            filterParts.push(`loop=loop=${Math.ceil(scene.duration / videoDuration)}:size=1:start=0`);
          }
          
          if (scene.effect?.type) {
            const effectFilter = this.getEffectFilter(scene.effect);
            if (effectFilter) {
              filterParts.push(effectFilter);
            }
          }
        }

        // Add duration enforcement and fades
        filterParts.push(`trim=duration=${scene.duration}`);
        filterParts.push('setpts=PTS-STARTPTS');

        const fadeInDuration = Math.min(0.5, scene.duration * 0.1);
        const fadeOutDuration = Math.min(0.5, scene.duration * 0.1);
        
        // Ensure fade durations are valid
        if (fadeInDuration > 0 && fadeOutDuration > 0) {
          filterParts.push(`fade=in:0:${Math.round(fadeInDuration * 25)}`);
          filterParts.push(`fade=out:${Math.round((scene.duration - fadeOutDuration) * 25)}:${Math.round(fadeOutDuration * 25)}`);
        }

        // Join all filter parts with commas, ensuring no empty filters
        const filterChain = filterParts.filter(part => part.length > 0).join(',');
        
        console.log(`Scene ${index} filter chain:`, filterChain);

        command
          .videoFilter(filterChain)
          .duration(scene.duration)
          .outputOptions([
            '-r', '25', // Ensure consistent framerate
            '-vsync', '1', // Ensure A/V sync
            '-shortest', // Don't loop beyond specified duration
            '-avoid_negative_ts', 'make_zero' // Prevent negative timestamps
          ])
          .on('start', cmd => console.log(`Processing scene ${index} command:`, cmd))
          .on('progress', progress => console.log(`Scene ${index} progress:`, progress))
          .on('stderr', stderrLine => console.log(`Scene ${index} stderr:`, stderrLine))
          .on('error', (err, stdout, stderr) => {
            console.error(`Scene ${index} error:`, { error: err.message, stdout, stderr });
            reject(new Error(`Scene ${index} processing failed: ${err.message}`));
          })
          .on('end', () => {
            // Verify the output file exists and has a non-zero size
            if (!fs.existsSync(outputPath) || fs.statSync(outputPath).size === 0) {
              reject(new Error(`Output file for scene ${index} is missing or empty`));
              return;
            }

            // Verify output dimensions and duration
            ffmpeg.ffprobe(outputPath, (err, metadata) => {
              if (err) {
                reject(new Error(`Failed to verify output for scene ${index}: ${err.message}`));
                return;
              }

              const videoStream = metadata.streams.find(s => s.codec_type === 'video');
              if (!videoStream || videoStream.width !== 1080 || videoStream.height !== 1920) {
                reject(new Error(`Scene ${index} output has incorrect dimensions: ${videoStream?.width}x${videoStream?.height}, expected 1080x1920`));
                return;
              }

              // Verify duration matches expected duration
              const actualDuration = metadata.format.duration || 0;
              if (Math.abs(actualDuration - scene.duration) > 0.1) { // Allow 100ms tolerance
                console.warn(`Scene ${index} duration mismatch: expected ${scene.duration}s, got ${actualDuration}s`);
              }

              resolve(outputPath);
            });
          })
          .save(outputPath);
      });
    });
  }

  private getFFmpegTransition(transitionType: TransitionType): string {
    // Map our transition types to valid FFmpeg xfade transitions
    switch (transitionType) {
      case 'fade':
        return 'fade';
      case 'crossfade':
        return 'fade';
      case 'zoom_in':
        return 'circleclose';
      case 'zoom_out':
        return 'circleopen';
      case 'slide_left':
        return 'slideleft';
      case 'slide_right':
        return 'slideright';
      case 'push_left':
        return 'wipeleft';
      case 'push_right':
        return 'wiperight';
      case 'blur':
        return 'pixelize';
      case 'flash_white':
        return 'fadewhite';
      case 'glitch':
        return 'pixelize';
      case 'none':
        return 'fade'; // Default to fade for 'none'
      default:
        return 'fade'; // Default transition
    }
  }

  // Combine processed scenes with transitions
  async combineScenes(scenePaths: string[], scenes: VideoScene[]): Promise<string> {
    console.log('Combining scenes:', scenePaths);
    
    if (scenePaths.length === 0) {
      throw new Error('No scenes to combine');
    }

    if (scenePaths.length !== scenes.length) {
      throw new Error('Scene paths count does not match scenes count');
    }

    // Verify all scene files exist and have valid video streams
    await Promise.all(scenePaths.map(path => this.verifyMediaFile(path, 'video')));

    // First pass: normalize all videos to the same framerate and timebase
    const normalizedScenes: string[] = [];
    try {
      for (const scenePath of scenePaths) {
        const normalizedPath = this.tempFileManager.createTempFilePath('normalized', '.mp4');
        await this.normalizeVideo(scenePath, normalizedPath);
        normalizedScenes.push(normalizedPath);
      }

      // Second pass: combine normalized scenes
      return await this.combineNormalizedScenes(normalizedScenes, scenes);
    } catch (error) {
      // Clean up normalized files on error
      normalizedScenes.forEach(path => {
        try { fs.unlinkSync(path); } catch (e) { /* ignore cleanup errors */ }
      });
      throw error;
    }
  }

  private async normalizeVideo(inputPath: string, outputPath: string): Promise<void> {
    return new Promise((resolve, reject) => {
      ffmpeg(inputPath)
        .outputOptions([
          '-c:v', 'libx264',
          '-preset', 'ultrafast',
          '-crf', '28',
          '-maxrate', '2500k',
          '-bufsize', '5000k',
          '-r', '25', // Force 25fps
          '-pix_fmt', 'yuv420p',
          '-movflags', '+faststart',
          '-vsync', 'cfr', // Constant frame rate
          '-video_track_timescale', '25000' // Consistent timebase
        ])
        .on('start', cmd => console.log('Normalizing video command:', cmd))
        .on('progress', progress => console.log('Normalization progress:', progress))
        .on('error', err => reject(new Error(`Video normalization failed: ${err.message}`)))
        .on('end', () => resolve())
        .save(outputPath);
    });
  }

  private async combineNormalizedScenes(normalizedPaths: string[], scenes: VideoScene[]): Promise<string> {
    const outputPath = this.tempFileManager.createTempFilePath('final', '.mp4');
    const transitionDuration = 0.5; // 500ms transitions

    return new Promise((resolve, reject) => {
      let command = ffmpeg();
      
      // Add all input files
      normalizedPaths.forEach(path => {
        command = command.input(path);
      });

      // Build the complex filter for transitions
      const filterComplex = this.buildTransitionFilter(scenes, transitionDuration);
      
      command
        .complexFilter(filterComplex.filter, [filterComplex.output])
        .outputOptions([
          '-c:v', 'libx264',
          '-preset', 'ultrafast',
          '-crf', '28',
          '-maxrate', '2500k',
          '-bufsize', '5000k',
          '-pix_fmt', 'yuv420p',
          '-movflags', '+faststart',
          '-thread_queue_size', '512',
          '-max_muxing_queue_size', '1024',
          '-r', '25', // Ensure consistent framerate
          '-vsync', '1', // Ensure A/V sync
          '-avoid_negative_ts', 'make_zero' // Prevent negative timestamps
        ])
        .on('start', cmd => {
          console.log('Combining scenes command:', cmd);
          console.log('Filter complex:', filterComplex);
        })
        .on('progress', progress => console.log('Combination progress:', progress))
        .on('error', (err, stdout, stderr) => {
          console.error('Scene combination error:', {
            error: err.message,
            stdout,
            stderr
          });
          reject(new Error(`Scene combination failed: ${err.message}`));
        })
        .on('end', () => {
          // Verify the final output
          ffmpeg.ffprobe(outputPath, (err, metadata) => {
            if (err) {
              reject(new Error(`Failed to verify combined output: ${err.message}`));
              return;
            }

            const totalDuration = scenes.reduce((sum, scene) => sum + scene.duration, 0);
            const actualDuration = metadata.format.duration || 0;
            
            console.log('Combined video duration check:', {
              expected: totalDuration,
              actual: actualDuration,
              difference: Math.abs(actualDuration - totalDuration)
            });

            resolve(outputPath);
          });
        })
        .save(outputPath);
    });
  }

  private buildTransitionFilter(scenes: VideoScene[], transitionDuration: number): { filter: string[], output: string } {
    if (scenes.length === 1) {
        return { filter: [], output: '0:v' };
    }

    const filters: string[] = [];
    let lastOutput = '0:v';
    let cumulativeOffset = 0;
    
    for (let i = 1; i < scenes.length; i++) {
        const inputLabel = `${i}:v`;
        const outputLabel = `v${i}`;
        const transitionType = scenes[i - 1].transition?.type || 'fade';
        const transition = this.getFFmpegTransition(transitionType);
        
        // Calculate cumulative offset based on previous scene duration
        cumulativeOffset += scenes[i - 1].duration - transitionDuration;
        
        console.log(`Scene ${i} transition:`, {
            previousDuration: scenes[i - 1].duration,
            transitionDuration,
            cumulativeOffset,
            transition
        });
        
        filters.push(`[${lastOutput}][${inputLabel}]xfade=transition=${transition}:duration=${transitionDuration}:offset=${cumulativeOffset}[${outputLabel}]`);
        lastOutput = outputLabel;
    }

    return {
        filter: filters,
        output: lastOutput
    };
  }

  // Add audio and captions to the final video
  private async addAudioAndCaptions(
    videoPath: string,
    voiceoverPath: string,
    backgroundMusicPath: string | null,
    captionsPath: string
  ): Promise<string> {
    console.log('Adding audio and captions with:', {
      videoPath,
      voiceoverPath,
      backgroundMusicPath,
      captionsPath
    });

    // Verify all required files exist
    if (!fs.existsSync(videoPath)) throw new Error('Video file not found');
    if (!fs.existsSync(voiceoverPath)) throw new Error('Voiceover file not found');
    if (backgroundMusicPath && !fs.existsSync(backgroundMusicPath)) throw new Error('Background music file not found');
    if (!fs.existsSync(captionsPath)) throw new Error('Captions file not found');
    
    const outputPath = this.tempFileManager.createTempFilePath('final', '.mp4');
    // Adjust volume levels for better balance
    const voiceVolume = 1.0;
    const musicVolume = backgroundMusicPath ? 0.6 : 0;

    // Get voiceover duration
    const voiceoverDuration = await new Promise<number>((resolve, reject) => {
        ffmpeg.ffprobe(voiceoverPath, (err, metadata) => {
            if (err || !metadata?.format?.duration) {
                reject(new Error(`Failed to get voiceover duration: ${err?.message || 'Invalid metadata'}`));
                return;
            }
            resolve(metadata.format.duration);
        });
    });

    console.log('Voiceover duration:', voiceoverDuration);

    // Verify input files have valid streams
    await Promise.all([
        this.verifyMediaFile(videoPath, 'video'),
        this.verifyMediaFile(voiceoverPath, 'audio'),
        ...(backgroundMusicPath ? [this.verifyMediaFile(backgroundMusicPath, 'audio')] : [])
    ]);

    return new Promise((resolve, reject) => {
        let command = ffmpeg(videoPath)
            .input(voiceoverPath);

        if (backgroundMusicPath) {
            command = command.input(backgroundMusicPath);
        }

        // Define type for filter complex
        type FilterComplexEntry = {
            filter: string;
            options: string | Record<string, string | number>;
            inputs: string | string[];
            outputs: string[];
        };

        // Build filter complex array with proper typing
        const filterComplex: FilterComplexEntry[] = [];
        
        // First ensure all audio streams are at the same sample rate
        filterComplex.push(
            {
                filter: 'aresample',
                options: '48000',
                inputs: '1:a',
                outputs: ['voice_resampled']
            }
        );

        if (backgroundMusicPath) {
            filterComplex.push(
                {
                    filter: 'aresample',
                    options: '48000',
                    inputs: '2:a',
                    outputs: ['music_resampled']
                }
            );
        }

        // Add video duration handling
        filterComplex.push({
            filter: 'trim',
            options: `duration=${voiceoverDuration}`,
            inputs: '0:v',
            outputs: ['trimmed']
        });

        // Add ASS subtitle filter
        filterComplex.push({
            filter: 'ass',
            options: captionsPath,
            inputs: 'trimmed',
            outputs: ['subtitled']
        });
        
        if (backgroundMusicPath) {
            // Enhanced audio processing chain
            filterComplex.push(
                // Process voiceover with properly escaped compand parameters
                {
                    filter: 'compand',
                    options: '0.3\\,0.8\\:1\\,1.2\\:-90/-60\\|-60/-40\\|-40/-30\\|-30/-20\\:6\\:0\\:0\\:0',
                    inputs: 'voice_resampled',
                    outputs: ['voice_compressed']
                },
                // Apply volume after compression
                {
                    filter: 'volume',
                    options: voiceVolume.toString(),
                    inputs: 'voice_compressed',
                    outputs: ['voice_final']
                },
                // Split voice stream for multiple uses
                {
                    filter: 'asplit',
                    options: '2',
                    inputs: 'voice_final',
                    outputs: ['voice_final_1', 'voice_final_2']
                },
                // Process background music
                {
                    filter: 'lowpass',
                    options: 'f=6000',
                    inputs: 'music_resampled',
                    outputs: ['music_filtered']
                },
                {
                    filter: 'volume',
                    options: musicVolume.toString(),
                    inputs: 'music_filtered',
                    outputs: ['music_vol']
                },
                // Add fade out to music
                {
                    filter: 'afade',
                    options: `t=out:st=${voiceoverDuration-1}:d=1`,
                    inputs: 'music_vol',
                    outputs: ['music_faded']
                },
                // Less aggressive sidechaining with proper sync
                {
                    filter: 'sidechaincompress',
                    options: `threshold=0.12:ratio=4:attack=20:release=300`,
                    inputs: ['music_faded', 'voice_final_1'],
                    outputs: ['music_ducked']
                },
                // Set channel layouts before merging
                {
                    filter: 'aformat',
                    options: 'sample_fmts=fltp:channel_layouts=mono',
                    inputs: 'voice_final_2',
                    outputs: ['voice_formatted']
                },
                {
                    filter: 'aformat',
                    options: 'sample_fmts=fltp:channel_layouts=stereo',
                    inputs: 'music_ducked',
                    outputs: ['music_formatted']
                },
                // Final mix with proper sync
                {
                    filter: 'amerge',
                    options: {
                        inputs: 2
                    },
                    inputs: ['voice_formatted', 'music_formatted'],
                    outputs: ['merged_audio']
                },
                // Ensure consistent audio levels
                {
                    filter: 'dynaudnorm',
                    options: 'f=150:g=15',
                    inputs: 'merged_audio',
                    outputs: ['final_audio']
                }
            );
        } else {
            // Simple voiceover processing
            filterComplex.push(
                {
                    filter: 'compand',
                    options: '0.3\\,0.8\\:1\\,1.2\\:-90/-60\\|-60/-40\\|-40/-30\\|-30/-20\\:6\\:0\\:0\\:0',
                    inputs: 'voice_resampled',
                    outputs: ['voice_compressed']
                },
                {
                    filter: 'volume',
                    options: voiceVolume.toString(),
                    inputs: 'voice_compressed',
                    outputs: ['voice_norm']
                },
                {
                    filter: 'dynaudnorm',
                    options: 'f=150:g=15',
                    inputs: 'voice_norm',
                    outputs: ['final_audio']
                }
            );
        }

        // Apply complex filter and map the outputs with proper sync options
        command
            .complexFilter(filterComplex)
            .outputOptions([
                '-map', '[subtitled]',
                '-map', '[final_audio]',
                '-c:v', 'libx264',
                '-c:a', 'aac',
                '-b:a', '192k',
                '-ac', '2',
                '-ar', '48000',
                '-vsync', '1',
                '-async', '1',
                '-max_muxing_queue_size', '1024',
                '-movflags', '+faststart'
            ])
            .on('start', cmd => {
                console.log('Final assembly command:', cmd);
                console.log('Filter complex:', JSON.stringify(filterComplex, null, 2));
            })
            .on('progress', progress => console.log('Final assembly progress:', progress))
            .on('stderr', line => console.log('FFmpeg stderr:', line))
            .on('error', (err, stdout, stderr) => {
                console.error('Final assembly error:', {
                    error: err.message,
                    stdout,
                    stderr
                });
                reject(new Error(`Final assembly failed: ${err.message}`));
            })
            .on('end', async () => {
                try {
                    // Verify the output file
                    if (!fs.existsSync(outputPath)) {
                        throw new Error('Output file not created');
                    }
                    
                    const stats = fs.statSync(outputPath);
                    if (stats.size === 0) {
                        throw new Error('Output file is empty');
                    }

                    // Verify the output has both video and audio streams
                    await this.verifyMediaFile(outputPath, 'video');
                    await this.verifyMediaFile(outputPath, 'audio');
                    
                    // Verify final duration matches voiceover
                    const finalDuration = await new Promise<number>((resolve, reject) => {
                        ffmpeg.ffprobe(outputPath, (err, metadata) => {
                            if (err || !metadata?.format?.duration) {
                                reject(new Error(`Failed to verify final duration: ${err?.message || 'Invalid metadata'}`));
                                return;
                            }
                            resolve(metadata.format.duration);
                        });
                    });

                    if (Math.abs(finalDuration - voiceoverDuration) > 0.5) { // Allow 0.5s tolerance
                        console.warn('Final duration mismatch:', {
                            expected: voiceoverDuration,
                            actual: finalDuration
                        });
                    }
                    
                    console.log('✅ Final video assembly completed successfully');
                    resolve(outputPath);
                } catch (error) {
                    reject(error);
                }
            });

        command.save(outputPath);
    });
  }

  // Helper method to verify media files
  private async verifyMediaFile(filePath: string, type: 'video' | 'audio'): Promise<void> {
    return new Promise((resolve, reject) => {
      ffmpeg.ffprobe(filePath, (err, metadata) => {
        if (err) {
          reject(new Error(`Failed to probe ${type} file: ${err.message}`));
          return;
        }

        const stream = metadata.streams.find(s => s.codec_type === type);
        if (!stream) {
          reject(new Error(`No ${type} stream found in file: ${filePath}`));
          return;
        }

        console.log(`✅ Verified ${type} file:`, {
          path: filePath,
          codec: stream.codec_name,
          duration: metadata.format.duration
        });
        
        resolve();
      });
    });
  }

  async assembleVideo(
    scenes: VideoScene[],
    sceneMedia: SceneMedia[],
    voiceoverPath: string,
    captionsPath: string,
    backgroundMusicPath: string | null,
    tone: ReelTone
  ): Promise<string> {
    try {
      console.log('Starting staged video assembly with:', {
        scenes: scenes.length,
        media: sceneMedia.length,
        hasBackgroundMusic: !!backgroundMusicPath
      });

      // Validate inputs
      if (scenes.length !== sceneMedia.length) {
        throw new Error('Scene count does not match media count');
      }

      // 1. Get voiceover duration and adjust scene timings
      const voiceoverDuration = await new Promise<number>((resolve, reject) => {
        if (!fs.existsSync(voiceoverPath)) {
          reject(new Error(`Voiceover file not found at path: ${voiceoverPath}`));
          return;
        }

        ffmpeg.ffprobe(voiceoverPath, (err, metadata) => {
          if (err || !metadata?.format?.duration) {
            reject(new Error(`Failed to get voiceover metadata: ${err?.message || 'Invalid metadata'}`));
            return;
          }
          resolve(metadata.format.duration);
        });
      });

      const totalSceneDuration = scenes.reduce((sum, scene) => sum + scene.duration, 0);
      const durationRatio = voiceoverDuration / totalSceneDuration;
      
      scenes = scenes.map(scene => ({
        ...scene,
        duration: scene.duration * durationRatio
      }));

      // 2. Process each scene individually
      const processedScenePaths: string[] = [];
      for (let i = 0; i < scenes.length; i++) {
        const scene = scenes[i];
        const media = sceneMedia[i].primary?.[0];
        
        if (!media?.localPath) {
          throw new Error(`Missing media for scene ${i}`);
        }

        const processedPath = await this.processScene(
          media.localPath,
          scene,
          i,
          media.type
        );
        processedScenePaths.push(processedPath);
      }

      // 3. Combine scenes with transitions
      const combinedVideoPath = await this.combineScenes(processedScenePaths, scenes);

      // 4. Add audio and captions
      const finalVideoPath = await this.addAudioAndCaptions(
        combinedVideoPath,
        voiceoverPath,
        backgroundMusicPath,
        captionsPath
      );

      // Cleanup intermediate files
      processedScenePaths.forEach(path => this.tempFileManager.removeFile(path));
      this.tempFileManager.removeFile(combinedVideoPath);

      return finalVideoPath;
    } catch (error: unknown) {
      console.error('Error in staged video assembly:', error);
      throw error;
    }
  }

  // Add method to clean up all temporary files
  cleanup(): void {
    this.tempFileManager.cleanup();
  }
} 