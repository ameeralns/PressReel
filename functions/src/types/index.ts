export type ReelStatus = 
  | 'processing'
  | 'analyzing'
  | 'generatingVoiceover'
  | 'gatheringVisuals'
  | 'assemblingVideo'
  | 'finalizing'
  | 'completed'
  | 'failed'
  | 'cancelled';

export type ReelTone = 'professional' | 'casual' | 'dramatic';

export type VisualType = 'b-roll' | 'static' | 'talking' | 'overlay';

export type TransitionType = 
  | 'fade'           // Simple fade transition
  | 'crossfade'      // Smooth crossfade between scenes
  | 'zoom_in'        // Zoom into the next scene
  | 'zoom_out'       // Zoom out to the next scene
  | 'slide_left'     // Slide to the left
  | 'slide_right'    // Slide to the right
  | 'push_left'      // Push to the left
  | 'push_right'     // Push to the right
  | 'blur'           // Blur transition
  | 'flash_white'    // Flash to white
  | 'glitch'         // Glitch effect transition
  | 'none';          // Direct cut

export type VideoEffect = 
  | 'ken_burns'      // Ken Burns effect for images
  | 'zoom_in'        // Gradual zoom in
  | 'zoom_out'       // Gradual zoom out
  | 'pan_left'       // Pan left
  | 'pan_right'      // Pan right
  | 'tilt_up'        // Tilt up
  | 'tilt_down'      // Tilt down
  | 'blur_edges'     // Blur edges effect
  | 'vignette'       // Vignette effect
  | 'color_boost'    // Enhance colors
  | 'dramatic'       // High contrast look
  | 'none';          // No effect

export interface TransitionConfig {
  type: TransitionType;
  duration: number;     // Duration in seconds
  params?: {           // Optional parameters for the transition
    intensity?: number; // For effects like blur or glitch
    color?: string;    // For flash transitions
    direction?: string; // For slide/push transitions
  };
}

export interface EffectConfig {
  type: VideoEffect;
  intensity?: number;   // Effect intensity (0-1)
  startTime?: number;   // When to start the effect
  duration?: number;    // How long to apply the effect
  params?: {           // Additional effect parameters
    scale?: number;    // For zoom effects
    speed?: number;    // For pan/tilt effects
    color?: string;    // For color effects
  };
}

export interface ContextAnalysis {
  mainTopic: string;
  category: string;
  keyEntities: {
    people: string[];
    organizations: string[];
    events: string[];
  };
  relatedThemes: string[];
  visualConcepts: string[];
  targetAudience: string;
  mood: string;
}

export interface VideoScene {
  id: string;
  startTime: number;
  duration: number;
  description: string;
  primaryKeywords: string[];
  secondaryKeywords: string[];
  mood: string;
  visualType: VisualType;
  transition: TransitionConfig;
  effect: EffectConfig;
  visualRequirements?: string[];
}

export interface VideoAnalysis {
  contextAnalysis: ContextAnalysis;
  scenes: VideoScene[];
  totalDuration: number;
  mainVisualTheme: string;
  musicMood?: string;
  captionStyle?: string;
  visualMotifs: string[];
  defaultTransition: TransitionType;
  defaultEffect: VideoEffect;
}

export interface SceneMedia {
  primary: PixabayMedia[];
  background: PixabayMedia[];
  overlays: PixabayMedia[];
}

export interface PixabayMedia {
  type: 'video' | 'image';
  url: string;
  width: number;
  height: number;
  localPath?: string; // Local temporary file path after download
  isHorizontal?: boolean; // Whether the media is in horizontal format
}

export interface AiReel {
  id?: string;
  scriptId: string;
  status: ReelStatus;
  progress: number;
  createdAt: Date;
  updatedAt: Date;
  videoURL?: string;
  thumbnailURL?: string;
  voiceId: string;
  tone: ReelTone;
  userId: string;
  error?: string;
} 