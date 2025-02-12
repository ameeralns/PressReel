import * as dotenv from 'dotenv';
import * as path from 'path';

// Load environment variables from .env file
const envPath = path.resolve(__dirname, '../.env');
console.log('Loading environment variables from:', envPath);
dotenv.config({ path: envPath });

// Debug log environment variables (without showing actual values)
console.log('Environment variables loaded:', {
  OPENAI_API_KEY: !!process.env.OPENAI_API_KEY,
  PIXABAY_API_KEY: !!process.env.PIXABAY_API_KEY,
  ELEVENLABS_API_KEY: !!process.env.ELEVENLABS_API_KEY,
  JAMENDO_API_KEY: !!process.env.JAMENDO_API_KEY,
  PEXELS_API_KEY: !!process.env.PEXELS_API_KEY,
});

interface Config {
  openai: {
    apiKey: string;
  };
  pixabay: {
    apiKey: string;
  };
  elevenLabs: {
    apiKey: string;
  };
  jamendo: {
    apiKey: string;
  };
  pexels: {
    apiKey: string;
  };
}

const config: Config = {
  openai: {
    apiKey: process.env.OPENAI_API_KEY || '',
  },
  pixabay: {
    apiKey: process.env.PIXABAY_API_KEY || '',
  },
  elevenLabs: {
    apiKey: process.env.ELEVENLABS_API_KEY || '',
  },
  jamendo: {
    apiKey: process.env.JAMENDO_API_KEY || '',
  },
  pexels: {
    apiKey: process.env.PEXELS_API_KEY || '',
  },
};

// Validate required environment variables
const requiredEnvVars = [
  { key: 'OPENAI_API_KEY', value: config.openai.apiKey },
  { key: 'PIXABAY_API_KEY', value: config.pixabay.apiKey },
  { key: 'ELEVENLABS_API_KEY', value: config.elevenLabs.apiKey },
  { key: 'JAMENDO_API_KEY', value: config.jamendo.apiKey },
  { key: 'PEXELS_API_KEY', value: config.pexels.apiKey },
];

for (const { key, value } of requiredEnvVars) {
  if (!value) {
    console.error(`Missing required environment variable: ${key}`);
    console.error('Current environment:', process.env);
    throw new Error(`Missing required environment variable: ${key}`);
  }
}

export default config; 