/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { DocumentSnapshot, FieldValue } from 'firebase-admin/firestore';
import { VideoAnalysisService } from './services/videoAnalysis';
import { PixabayService } from './services/pixabay';
import { PexelsService } from './services/pexels';
import { JamendoService } from './services/jamendo';
import { ElevenLabsService } from './services/elevenLabs';
import { WhisperService } from './services/whisper';
import { FFmpegService } from './services/ffmpeg';
import { updateReelStatus, handleError } from './utils/status';
import { AiReel, SceneMedia, ReelTone } from './types';
import * as fs from 'fs';
import ffmpeg from 'fluent-ffmpeg';
import axios from 'axios';
import { TempFileManager } from './utils/tempFileManager';
import { Bucket } from '@google-cloud/storage';
import path from 'path';

// Initialize Firebase Admin with explicit configuration
try {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: 'pressreel',
      storageBucket: 'pressreel.appspot.com'
    });
    console.log('✅ Firebase Admin initialized successfully');
  } else {
    console.log('✅ Firebase Admin already initialized');
  }
} catch (error) {
  console.error('❌ Failed to initialize Firebase Admin:', error);
  throw error; // Re-throw to prevent functions from starting with bad initialization
}

// Initialize services
const videoAnalysis = new VideoAnalysisService();
const elevenLabs = new ElevenLabsService();
const pixabay = new PixabayService();
const pexels = new PexelsService();
const ffmpegService = new FFmpegService();
const jamendo = new JamendoService();

// Main function to handle reel generation
export const generateAiReel = onDocumentCreated({
  document: 'aiReels/{reelId}',
  timeoutSeconds: 540,
  memory: '2GiB'
}, async (event) => {
  console.log('🚀 generateAiReel function triggered');
  
  const snap = event.data as DocumentSnapshot;
  if (!snap) {
    console.error('❌ No data associated with the event');
    return;
  }
  
  const reelId = event.params.reelId;
  const reel = snap.data() as AiReel;
  console.log('📄 Reel data:', { reelId, ...reel });

  // Get temp file manager instance
  const tempFileManager = TempFileManager.getInstance();
  
  try {
    // Initial status update
    await updateReelStatus(reelId, 'processing');
    
    // 1. Analyze script
    console.log('🔍 Starting script analysis...');
    await updateReelStatus(reelId, 'analyzing');
    const analysis = await videoAnalysis.analyzeScript(reel.scriptId, reel.tone);
    console.log('✅ Script analysis complete:', analysis);
    
    // 2. Generate voiceover
    console.log('🎙 Starting voiceover generation...');
    await updateReelStatus(reelId, 'generatingVoiceover');
    const scriptDoc = await admin.firestore().collection('scripts').doc(reel.scriptId).get();
    if (!scriptDoc.exists) {
      throw new Error('Script document not found');
    }
    const scriptContent = scriptDoc.data()?.content;
    if (!scriptContent) {
      throw new Error('Script content is missing');
    }
    console.log('📝 Retrieved script content:', scriptContent);
    const voiceoverPath = await elevenLabs.generateVoiceover(scriptContent, reel.voiceId, reel.tone);
    tempFileManager.trackFile(voiceoverPath);
    console.log('✅ Voiceover generated:', voiceoverPath);
    
    // 3. Generate captions
    console.log('📺 Generating captions...');
    const whisper = new WhisperService(reel.tone);
    const captionsPath = await whisper.generateCaptions(voiceoverPath);
    tempFileManager.trackFile(captionsPath);
    console.log('✅ Captions generated:', captionsPath);
    
    // 4. Gather visuals
    console.log('🎬 Gathering visuals...');
    await updateReelStatus(reelId, 'gatheringVisuals');
    const sceneMedia: SceneMedia[] = [];
    for (const scene of analysis.scenes) {
      console.log('🔍 Fetching media for scene:', scene);
      try {
        // Try Pexels first
        const media = await pexels.fetchMediaForScene(scene);
        if (media) {
          sceneMedia.push(media);
          continue;
        }
      } catch (error) {
        console.log('Pexels search failed, falling back to Pixabay:', error);
        try {
          // Fallback to Pixabay
          const media = await pixabay.fetchMediaForScene(scene);
          if (media) {
            sceneMedia.push(media);
          }
        } catch (pixabayError) {
          console.error('Both Pexels and Pixabay search failed:', pixabayError);
          throw new Error(`Failed to fetch media for scene: ${scene.description}`);
        }
      }
    }
    console.log('✅ All scene media gathered');

    // 5. Fetch background music
    console.log('🎵 Fetching background music...');
    let backgroundMusicPath: string | null = null;
    try {
      console.log('🎵 Starting background music fetch with:', {
        tone: reel.tone,
        mood: analysis.contextAnalysis.mood
      });
      
      backgroundMusicPath = await fetchAndDownloadMusic(reel.tone, analysis.contextAnalysis.mood);
      
      if (backgroundMusicPath) {
        console.log('✅ Successfully downloaded background music to:', backgroundMusicPath);
        tempFileManager.trackFile(backgroundMusicPath);
      } else {
        console.warn('⚠️ No background music was found or downloaded');
      }
    } catch (error) {
      console.error('❌ Failed to fetch background music:', error);
      // Log additional error details if available
      if (error instanceof Error) {
        console.error('Error details:', {
          message: error.message,
          stack: error.stack
        });
      }
      // Continue without background music
      console.log('⚠️ Proceeding without background music');
    }
    
    // 6. Assemble video
    console.log('🎥 Starting video assembly...');
    await updateReelStatus(reelId, 'assemblingVideo');
    const videoPath = await ffmpegService.assembleVideo(
      analysis.scenes,
      sceneMedia,
      voiceoverPath,
      captionsPath,
      backgroundMusicPath,
      reel.tone
    );
    tempFileManager.trackFile(videoPath);
    console.log('✅ Video assembled:', videoPath);
    
    // 7. Generate thumbnail
    console.log('🖼 Generating thumbnail...');
    await updateReelStatus(reelId, 'finalizing');
    const thumbnailPath = await generateThumbnail(videoPath);
    tempFileManager.trackFile(thumbnailPath);
    console.log('✅ Thumbnail generated:', thumbnailPath);
    
    // 8. Upload to Firebase Storage
    console.log('⬆️ Starting upload process...');
    const bucket = admin.storage().bucket();
    
    // Upload video and thumbnail
    const [videoURL, thumbnailURL] = await Promise.all([
      uploadToStorage(bucket, videoPath, `users/${reel.userId}/reels/${reelId}/final.mp4`, 'video/mp4'),
      uploadToStorage(bucket, thumbnailPath, `users/${reel.userId}/reels/${reelId}/thumbnail.jpg`, 'image/jpeg')
    ]);
    
    // Update reel document with completion
    console.log('📝 Updating reel document with URLs...');
    await updateReelStatus(reelId, 'completed');
    await admin.firestore().collection('aiReels').doc(reelId).update({
      videoURL,
      thumbnailURL,
      updatedAt: FieldValue.serverTimestamp()
    });
    
    // Cleanup all temporary files
    console.log('🧹 Cleaning up temporary files...');
    tempFileManager.cleanup();
    
    console.log('🎉 Video generation completed successfully!');
    
  } catch (error: unknown) {
    console.error('❌ Error in generateAiReel:', error);
    // Clean up all temporary files
    tempFileManager.cleanup();
    await handleError(reelId, error instanceof Error ? error : new Error('Unknown error occurred'));
  }
});

// Helper function to fetch and download background music
async function fetchAndDownloadMusic(tone: ReelTone, mood: string): Promise<string | null> {
  const tempFileManager = TempFileManager.getInstance();
  let retryCount = 0;
  const maxRetries = 3;

  while (retryCount < maxRetries) {
    try {
      const music = await jamendo.fetchBackgroundMusic(tone, mood);
      if (!music?.url) {
        console.log('❌ No valid music URL found');
        return null;
      }

      const musicPath = tempFileManager.createTempFilePath('bgm', '.mp3');
      
      const musicResponse = await axios({
        method: 'get',
        url: music.url,
        responseType: 'stream'
      });

      await new Promise<void>((resolve, reject) => {
        const writer = fs.createWriteStream(musicPath);
        musicResponse.data.pipe(writer);
        writer.on('finish', resolve);
        writer.on('error', (error) => {
          tempFileManager.removeFile(musicPath);
          reject(error);
        });
      });

      return musicPath;
    } catch (error) {
      console.error(`❌ Error fetching background music (attempt ${retryCount + 1}/${maxRetries}):`, error);
      retryCount++;
      
      if (retryCount === maxRetries) {
        console.error('❌ All attempts to fetch background music failed');
        return null;
      }
    }
  }
  return null;
}

// Helper function to generate thumbnail
async function generateThumbnail(videoPath: string): Promise<string> {
  console.log('Starting thumbnail generation for video:', videoPath);
  
  // First verify the video file exists and has a video stream
  if (!fs.existsSync(videoPath)) {
    console.error('Video file not found at path:', videoPath);
    throw new Error('Video file not found for thumbnail generation');
  }
  console.log('✅ Video file exists');

  // Probe the video file to verify it has a video stream
  await new Promise<void>((resolve, reject) => {
    console.log('Probing video file for streams...');
    ffmpeg.ffprobe(videoPath, (err, metadata) => {
      if (err) {
        console.error('FFprobe error:', err);
        reject(new Error(`Failed to probe video for thumbnail: ${err.message}`));
        return;
      }
      
      console.log('Video metadata:', JSON.stringify(metadata, null, 2));
      const videoStream = metadata.streams.find(s => s.codec_type === 'video');
      if (!videoStream) {
        console.error('No video stream found in metadata');
        reject(new Error('No video stream found in the input file'));
        return;
      }
      
      console.log('✅ Found video stream:', {
        codec: videoStream.codec_name,
        resolution: `${videoStream.width}x${videoStream.height}`,
        duration: videoStream.duration
      });
      
      resolve();
    });
  });

  // Properly separate path components for FFmpeg
  const folder = path.dirname(videoPath);
  const baseName = path.basename(videoPath, '.mp4');
  const filename = `${baseName}-thumb.jpg`;
  const thumbnailPath = path.join(folder, filename);
  
  console.log('Generating thumbnail at:', thumbnailPath);
  
  await new Promise<void>((resolve, reject) => {
    ffmpeg(videoPath)
      .screenshots({
        timestamps: ['50%'],
        folder,             // specify the output folder
        filename,           // specify the filename pattern
        size: '1280x720'
      })
      .on('start', (cmd) => {
        console.log('Started FFmpeg with command:', cmd);
      })
      .on('end', () => {
        if (fs.existsSync(thumbnailPath) && fs.statSync(thumbnailPath).size > 0) {
          console.log('✅ Thumbnail generated successfully');
          resolve();
        } else {
          reject(new Error('Thumbnail file is missing or empty'));
        }
      })
      .on('error', (err) => {
        console.error('FFmpeg thumbnail generation error:', err);
        reject(new Error(`Failed to generate thumbnail: ${err.message}`));
      });
  });

  return thumbnailPath;
}

// Helper function to upload to storage
async function uploadToStorage(
  bucket: Bucket,
  filePath: string,
  destination: string,
  contentType: string
): Promise<string> {
  await bucket.upload(filePath, {
    destination,
    metadata: { contentType }
  });
  await bucket.file(destination).makePublic();
  return `https://storage.googleapis.com/${bucket.name}/${destination}`;
}

// Function to handle reel cancellation
export const cancelAiReel = onCall({
  timeoutSeconds: 60,
  memory: '256MiB'
}, async (request) => {
  // Ensure user is authenticated
  if (!request.auth) {
    throw new Error('User must be authenticated');
  }
  
  const { reelId } = request.data;
  if (!reelId) {
    throw new Error('Reel ID is required');
  }
  
  try {
    const reelRef = admin.firestore().collection('aiReels').doc(reelId);
    const reelDoc = await reelRef.get();
    
    if (!reelDoc.exists) {
      throw new Error('Reel not found');
    }
    
    const reel = reelDoc.data() as AiReel;
    
    // Ensure user owns the reel
    if (reel.userId !== request.auth.uid) {
      throw new Error('Not authorized to cancel this reel');
    }
    
    // Only allow cancellation of processing reels
    if (!['processing', 'analyzing', 'generatingVoiceover', 'gatheringVisuals', 'assemblingVideo'].includes(reel.status)) {
      throw new Error('Can only cancel processing reels');
    }
    
    // Clean up any temporary files
    TempFileManager.getInstance().cleanup();
    
    await updateReelStatus(reelId, 'cancelled');
    return { success: true };
    
  } catch (error: any) {
    console.error('Error cancelling reel:', error);
    // Ensure cleanup happens even on error
    TempFileManager.getInstance().cleanup();
    throw new Error(error.message);
  }
});

// Function to fetch ElevenLabs voices
export const getElevenLabsVoices = onCall({
  timeoutSeconds: 60,
  memory: '256MiB'
}, async () => {
  console.log('Cloud Function: getElevenLabsVoices started');
  try {
    console.log('Calling ElevenLabs service getVoices method');
    const voices = await elevenLabs.getVoices();
    console.log('Successfully retrieved voices:', voices.length);
    return { voices };
  } catch (error: any) {
    console.error('Error in getElevenLabsVoices function:', error);
    console.error('Error stack:', error.stack);
    throw new HttpsError('internal', `Failed to fetch voices: ${error.message}`);
  }
});
