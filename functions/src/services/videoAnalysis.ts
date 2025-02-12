import OpenAI from 'openai';
import { VideoAnalysis, ReelTone } from '../types';
import * as admin from 'firebase-admin';
import config from '../config';

const openai = new OpenAI({
  apiKey: config.openai.apiKey
});

export class VideoAnalysisService {
  private createSystemPrompt(): string {
    return `You are an expert video producer specializing in creating 30-second news reels using stock footage from Pixabay. Your expertise includes sports journalism, current events, and viral content.

    CRITICAL REQUIREMENTS:
    1. Total video duration MUST be between 25-35 seconds
    2. MUST create 7-10 distinct scenes
    3. Each scene MUST have stock-footage-friendly keywords
    4. All visuals MUST be obtainable from Pixabay

    For each scene, you must provide:
    1. SPECIFIC, searchable keywords that will find relevant stock footage on Pixabay
       - Use common terms that would exist in stock footage libraries
       - Include both specific terms (e.g., "soccer stadium", "business meeting") 
       - And general terms (e.g., "crowd cheering", "office workspace")
       - Consider location-specific terms when relevant
       - Include emotional/atmospheric terms (e.g., "dramatic", "energetic")

    2. Scene timing:
       - Each scene should be 2-5 seconds
       - Total of all scenes MUST sum to 25-35 seconds
       - Timing should feel natural and match content pacing

    3. Visual continuity:
       - Scenes should flow logically
       - Mix of wide shots and close-ups
       - Balance between action and static shots
       - Consider visual progression

    Available Scene Types:
    - b-roll: Stock footage of events, locations, or actions
    - static: Still images or slow-moving shots
    - talking: People speaking or reacting
    - overlay: Text or graphic overlays

    Available Transitions:
    - fade: Simple fade transition (good for emotional moments)
    - crossfade: Smooth crossfade (good for flowing narrative)
    - zoom_in/zoom_out: Zoom transitions (good for emphasis)
    - slide_left/right: Slide transitions (good for progression)
    - push_left/right: Push transitions (good for temporal changes)
    - blur: Blur transition (good for dream sequences or memory)
    - flash_white: Flash transition (good for high energy moments)
    - glitch: Glitch effect (good for tech topics or tension)
    - none: Direct cut (good for impact)

    Available Effects:
    - ken_burns: Pan and zoom for static images
    - zoom_in/out: Gradual camera movement
    - pan_left/right: Horizontal movement
    - tilt_up/down: Vertical movement
    - blur_edges: Depth effect
    - vignette: Focus attention
    - color_boost: Enhance colors
    - dramatic: High contrast look

    Match transitions and effects to content:
    Sports: Dynamic transitions (zoom, push) + energetic effects
    Business: Professional transitions (fade, crossfade) + subtle effects
    Politics: Formal transitions (fade, slide) + minimal effects
    Entertainment: Creative transitions (glitch, flash) + dramatic effects`;
  }

  private createAnalysisPrompt(script: string, tone: ReelTone): string {
    return `Create a 30-second video reel breakdown for this script using Pixabay stock footage. Match the ${tone} tone.

    SCRIPT TO ANALYZE:
    "${script}"

    REQUIREMENTS:
    - Total duration: 25-35 seconds
    - Number of scenes: 7-10
    - Each scene: 2-5 seconds
    - Must use obtainable stock footage

    CRITICAL: You must respond with a valid JSON object with EXACTLY this structure:
    {
      "contextAnalysis": {
        "mainTopic": "string",
        "category": "string",
        "keyEntities": {
          "people": ["string"],
          "organizations": ["string"],
          "events": ["string"]
        },
        "relatedThemes": ["string"],
        "visualConcepts": ["string"],
        "targetAudience": "string",
        "mood": "string"
      },
      "scenes": [
        {
          "startTime": number,
          "duration": number,
          "description": "string",
          "primaryKeywords": ["string"],
          "secondaryKeywords": ["string"],
          "mood": "string",
          "visualType": "b-roll" | "static" | "talking" | "overlay",
          "transition": {
            "type": "string",
            "duration": number
          },
          "effect": {
            "type": "string",
            "intensity": number,
            "duration": number
          }
        }
      ],
      "overallDirection": {
        "mainVisualTheme": "string",
        "musicMood": "string",
        "captionStyle": "string",
        "visualMotifs": ["string"],
        "defaultTransition": "string",
        "defaultEffect": "string"
      }
    }

    IMPORTANT NOTES:
    1. The "scenes" array MUST contain 7-10 scenes
    2. Each scene duration MUST be between 2-5 seconds
    3. Total duration of all scenes MUST sum to 25-35 seconds
    4. All required fields MUST be present
    5. Response MUST be valid JSON

    For the ${tone} tone, ensure:
    ${tone === 'dramatic' ? '- Use intense, high-energy visuals\n- Bold transitions\n- Dynamic effects\n- Emotional impact' :
      tone === 'professional' ? '- Clean, corporate visuals\n- Subtle transitions\n- Minimal effects\n- Professional atmosphere' :
      '- Natural, relaxed visuals\n- Smooth transitions\n- Gentle effects\n- Casual feel'}`;
  }

  async analyzeScript(scriptId: string, tone: ReelTone): Promise<VideoAnalysis> {
    try {
      console.log('Starting script analysis for:', { scriptId, tone });
      
      // Verify Firebase Admin is initialized
      if (!admin.apps.length) {
        console.error('Firebase Admin not initialized in videoAnalysis.ts');
        throw new Error('Firebase Admin not initialized');
      }

      const db = admin.firestore();
      if (!db) {
        console.error('Firestore not available');
        throw new Error('Firestore not available');
      }

      // First, fetch the script from Firestore
      const scriptDoc = await db.collection('scripts').doc(scriptId).get();
      if (!scriptDoc.exists) {
        throw new Error('Script not found');
      }
      
      const scriptData = scriptDoc.data();
      if (!scriptData?.content) {
        throw new Error('Script content is missing');
      }
      console.log('Retrieved script content:', scriptData.content);

      console.log('Making OpenAI API request...');
      const completion = await openai.chat.completions.create({
        model: "gpt-4-turbo-preview",
        messages: [
          { role: "system", content: this.createSystemPrompt() },
          { role: "user", content: this.createAnalysisPrompt(scriptData.content, tone) }
        ],
        response_format: { type: "json_object" },
        temperature: 0.7
      });
      console.log('Received OpenAI response');

      const jsonString = completion.choices[0].message.content;
      console.log('Raw OpenAI response content:', jsonString);
      
      if (!jsonString) {
        throw new Error('Invalid response from OpenAI: Empty content');
      }

      console.log('Attempting to parse JSON response...');
      let analysis: VideoAnalysis;
      try {
        analysis = JSON.parse(jsonString) as VideoAnalysis;
        console.log('Parsed analysis structure:', {
          hasContextAnalysis: !!analysis.contextAnalysis,
          hasScenes: !!analysis.scenes,
          sceneCount: analysis.scenes?.length,
          analysisKeys: Object.keys(analysis)
        });
      } catch (parseError: any) {
        console.error('Failed to parse OpenAI response:', parseError);
        console.error('Invalid JSON response:', jsonString);
        throw new Error(`Invalid JSON response from OpenAI: ${parseError.message}`);
      }

      if (!analysis.scenes) {
        console.error('Invalid analysis structure:', analysis);
        throw new Error('OpenAI response missing scenes array');
      }

      console.log('Validating scene count...');
      // Validate scene count
      if (analysis.scenes.length < 7 || analysis.scenes.length > 10) {
        throw new Error(`Scene count must be between 7 and 10, got ${analysis.scenes.length}`);
      }

      console.log('Validating total duration...');
      // Validate total duration (25-35 seconds)
      const totalDuration = analysis.scenes.reduce((sum, scene) => sum + scene.duration, 0);
      
      // If duration is close to the valid range (within 2 seconds), adjust scene durations
      if (totalDuration >= 23 && totalDuration < 25) {
        console.log(`Adjusting scene durations from ${totalDuration} to match minimum duration...`);
        const adjustment = (25 - totalDuration) / analysis.scenes.length;
        analysis.scenes = analysis.scenes.map(scene => ({
          ...scene,
          duration: scene.duration + adjustment
        }));
        console.log('Adjusted scene durations:', analysis.scenes.map(s => s.duration));
      } else if (totalDuration > 35 && totalDuration <= 37) {
        console.log(`Adjusting scene durations from ${totalDuration} to match maximum duration...`);
        const adjustment = (totalDuration - 35) / analysis.scenes.length;
        analysis.scenes = analysis.scenes.map(scene => ({
          ...scene,
          duration: scene.duration - adjustment
        }));
        console.log('Adjusted scene durations:', analysis.scenes.map(s => s.duration));
      } else if (totalDuration < 23 || totalDuration > 37) {
        throw new Error(`Total duration must be between 25 and 35 seconds, got ${totalDuration}`);
      }

      // Recalculate start times based on adjusted durations
      let currentStartTime = 0;
      analysis.scenes = analysis.scenes.map(scene => {
        const adjustedScene = {
          ...scene,
          startTime: currentStartTime
        };
        currentStartTime += scene.duration;
        return adjustedScene;
      });

      console.log('Storing context analysis in Firestore...');
      try {
        // Create timestamp using FieldValue for more reliability
        const data = {
          contextAnalysis: analysis.contextAnalysis,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };
        
        await db.collection('scriptAnalysis').doc(scriptId).set(data);
        console.log('Successfully stored context analysis');
      } catch (firestoreError: any) {
        // Log detailed error information but don't fail
        console.error('Failed to store context analysis:', {
          error: firestoreError,
          message: firestoreError.message,
          code: firestoreError.code,
          details: firestoreError.details
        });
        
        // Fallback to using a regular Date object if FieldValue fails
        try {
          const fallbackData = {
            contextAnalysis: analysis.contextAnalysis,
            createdAt: new Date(),
            updatedAt: new Date()
          };
          await db.collection('scriptAnalysis').doc(scriptId).set(fallbackData);
          console.log('Successfully stored context analysis using fallback timestamp');
        } catch (fallbackError) {
          console.error('Failed to store context analysis with fallback timestamp:', fallbackError);
        }
      }

      console.log('Analysis complete:', analysis);
      return analysis;
    } catch (error: any) {
      console.error('Error analyzing script:', error);
      throw new Error(`Failed to analyze script: ${error.message}`);
    }
  }
} 