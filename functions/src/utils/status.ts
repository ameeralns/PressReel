import * as admin from 'firebase-admin';
import { ReelStatus } from '../types';
import { FieldValue } from 'firebase-admin/firestore';

export const getProgressForStatus = (status: ReelStatus): number => {
  switch (status) {
    case 'processing':
      return 0.0;
    case 'analyzing':
      return 0.1;
    case 'generatingVoiceover':
      return 0.3;
    case 'gatheringVisuals':
      return 0.5;
    case 'assemblingVideo':
      return 0.7;
    case 'finalizing':
      return 0.9;
    case 'completed':
      return 1.0;
    case 'failed':
    case 'cancelled':
      return 0.0;
    default:
      return 0.0;
  }
};

export async function updateReelStatus(
  reelId: string,
  status: string,
  error?: string
): Promise<void> {
  console.log('📊 Updating reel status:', { reelId, status, error });
  
  // Get the progress value for this status
  const progress = getProgressForStatus(status as ReelStatus);
  console.log(`Progress for ${status}: ${progress * 100}%`);

  try {
    const updateData = {
      status,
      error: error || null,
      progress,
      updatedAt: FieldValue.serverTimestamp()
    };

    console.log('Updating Firestore with:', updateData);
    await admin.firestore().collection('aiReels').doc(reelId).update(updateData);
    console.log('✅ Status update successful');
  } catch (error: any) {
    console.error('❌ Error in updateReelStatus:', error);
    // Fallback to regular timestamp if serverTimestamp fails
    const fallbackData = {
      status,
      error: error?.message || null,
      progress,
      updatedAt: new Date()
    };
    
    try {
      await admin.firestore().collection('aiReels').doc(reelId).update(fallbackData);
      console.log('✅ Status update successful using fallback timestamp');
    } catch (retryError) {
      console.error('❌ Failed to update status even with fallback:', retryError);
      throw retryError; // Re-throw if both attempts fail
    }
  }
}

export const handleError = async (reelId: string, error: Error) => {
  try {
    console.error(`Error processing reel ${reelId}:`, error);
    await updateReelStatus(reelId, 'failed', error.message);
  } catch (updateError) {
    // Log but don't throw to prevent infinite error loops
    console.error('Failed to handle error:', updateError);
    console.error('Original error:', error);
  }
}; 