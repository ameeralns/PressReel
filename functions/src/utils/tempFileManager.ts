import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import axios from 'axios';

export class TempFileManager {
  private static instance: TempFileManager;
  private trackedFiles: Set<string>;
  private readonly tempDir: string;

  private constructor() {
    this.trackedFiles = new Set<string>();
    this.tempDir = os.tmpdir();
  }

  public static getInstance(): TempFileManager {
    if (!TempFileManager.instance) {
      TempFileManager.instance = new TempFileManager();
    }
    return TempFileManager.instance;
  }

  /**
   * Downloads a file from a URL and saves it to a temporary location
   * @param url - URL to download from
   * @param prefix - Prefix for the temp file name
   * @param extension - File extension including the dot (e.g., '.mp4')
   * @returns The path to the downloaded file
   */
  public async downloadFile(url: string, prefix: string, extension: string): Promise<string> {
    const filePath = this.createTempFilePath(prefix, extension);
    
    try {
      const response = await axios({
        method: 'get',
        url: url,
        responseType: 'stream'
      });

      await new Promise<void>((resolve, reject) => {
        const writer = fs.createWriteStream(filePath);
        response.data.pipe(writer);
        writer.on('finish', resolve);
        writer.on('error', (error) => {
          this.removeFile(filePath);
          reject(error);
        });
      });

      return filePath;
    } catch (error) {
      this.removeFile(filePath);
      throw error;
    }
  }

  /**
   * Creates a temporary file path and tracks it
   * @param prefix - Prefix for the temp file name
   * @param extension - File extension including the dot (e.g., '.mp4')
   * @returns The full path to the temporary file
   */
  public createTempFilePath(prefix: string, extension: string): string {
    const fileName = `${prefix}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}${extension}`;
    const filePath = path.join(this.tempDir, fileName);
    this.trackFile(filePath);
    return filePath;
  }

  /**
   * Tracks an existing file for cleanup
   * @param filePath - Path to the file to track
   */
  public trackFile(filePath: string): void {
    if (filePath) {
      this.trackedFiles.add(filePath);
    }
  }

  /**
   * Removes a specific file from tracking and deletes it
   * @param filePath - Path to the file to remove
   */
  public removeFile(filePath: string): void {
    if (filePath && this.trackedFiles.has(filePath)) {
      try {
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      } catch (error) {
        console.error(`Failed to delete file ${filePath}:`, error);
      } finally {
        this.trackedFiles.delete(filePath);
      }
    }
  }

  /**
   * Cleans up all tracked temporary files
   */
  public cleanup(): void {
    console.log(`Cleaning up ${this.trackedFiles.size} temporary files...`);
    for (const filePath of this.trackedFiles) {
      try {
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
          console.log(`Deleted temporary file: ${filePath}`);
        }
      } catch (error) {
        console.error(`Failed to delete temporary file ${filePath}:`, error);
      }
    }
    this.trackedFiles.clear();
  }

  /**
   * Gets the number of tracked files
   */
  public getTrackedFilesCount(): number {
    return this.trackedFiles.size;
  }

  /**
   * Gets the list of currently tracked files
   */
  public getTrackedFiles(): string[] {
    return Array.from(this.trackedFiles);
  }
} 