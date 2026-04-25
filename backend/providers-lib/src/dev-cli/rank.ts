/* eslint import/no-extraneous-dependencies: ["error", {"devDependencies": true}] */
/* eslint-disable no-console */

/**
 * Interactive CLI tool for managing provider ranks.
 *
 * Usage:
 * - Run `npm run cli -- --rank` to launch the rank manager
 *
 * Controls:
 * - ↑↓ arrows: Navigate between providers
 * - ← (left arrow): Move selected provider down in rank
 * - → (right arrow): Move selected provider up in rank
 * - Ctrl+C or Q: Exit
 *
 * Changes are automatically saved to the provider files.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as readline from 'readline';

import { getBuiltinEmbeds, getBuiltinExternalSources, getBuiltinSources } from '@/entrypoint/providers';

type Provider = {
  id: string;
  name: string;
  type: 'source' | 'embed';
  rank: number;
  filePath?: string;
  mediaTypes?: string[];
};

function joinMediaTypes(mediaTypes: string[] | undefined) {
  if (mediaTypes) {
    const formatted = mediaTypes
      .map((type: string) => {
        return `${type[0].toUpperCase() + type.substring(1).toLowerCase()}s`;
      })
      .join(' / ');

    return `(${formatted})`;
  }
  return ''; // * Embed sources pass through here too
}

async function findProviderFile(providerId: string, type: 'source' | 'embed'): Promise<string | null> {
  const baseDir = path.join(process.cwd(), 'src', 'providers', type === 'source' ? 'sources' : 'embeds');

  // Search for files containing the provider ID
  try {
    const files = await fs.promises.readdir(baseDir, { recursive: true });
    for (const file of files) {
      if (file.endsWith('.ts')) {
        const filePath = path.join(baseDir, file);
        const content = await fs.promises.readFile(filePath, 'utf-8');
        if (content.includes(`id: '${providerId}'`) || content.includes(`id: "${providerId}"`)) {
          return filePath;
        }
      }
    }
  } catch {
    // Silently continue if file not found
  }

  return null;
}

async function updateProviderRank(filePath: string, newRank: number): Promise<boolean> {
  try {
    const content = await fs.promises.readFile(filePath, 'utf-8');

    // Find and replace the rank property
    const rankRegex = /rank:\s*\d+/g;
    const newContent = content.replace(rankRegex, `rank: ${newRank}`);

    if (newContent !== content) {
      await fs.promises.writeFile(filePath, newContent, 'utf-8');
      return true;
    }
  } catch {
    // Silently continue if update fails
  }

  return false;
}

function getAllProviders(): Provider[] {
  const sourceScrapers = [...getBuiltinSources(), ...getBuiltinExternalSources()].sort((a, b) => b.rank - a.rank);
  const embedScrapers = getBuiltinEmbeds().sort((a, b) => b.rank - a.rank);

  const sources: Provider[] = sourceScrapers.map((scraper) => ({
    id: scraper.id,
    name: scraper.name,
    type: 'source',
    rank: scraper.rank,
    mediaTypes: scraper.mediaTypes,
  }));

  const embeds: Provider[] = embedScrapers.map((embed) => ({
    id: embed.id,
    name: embed.name,
    type: 'embed',
    rank: embed.rank,
    mediaTypes: embed.mediaTypes,
  }));

  return [...sources, ...embeds];
}

export async function runRankManager() {
  const providers = getAllProviders();

  // Find file paths for all providers
  for (const provider of providers) {
    const filePath = await findProviderFile(provider.id, provider.type);
    if (filePath) {
      provider.filePath = filePath;
    }
  }

  // Check if we're in an interactive terminal
  if (!process.stdin.isTTY) {
    console.log('Use ↑↓ arrows to navigate, ←→ to change rank, Ctrl+C to exit');
    console.log('');
    providers.forEach((provider, index) => {
      const typeColor = provider.type === 'source' ? '[SOURCE]' : '[EMBED] ';
      const mediaTypes = joinMediaTypes(provider.mediaTypes);
      console.log(`${index + 1}. ${typeColor} [${provider.rank}] ${provider.name} ${mediaTypes}`.trim());
    });
    console.log('\n Interactive mode requires a TTY. Run in a terminal for full functionality.');
    return;
  }

  const currentProviders = [...providers];
  let selectedIndex = 0;

  const swapProviders = async (index1: number, index2: number, newSelectedIndex: number) => {
    const provider1 = currentProviders[index1];
    const provider2 = currentProviders[index2];

    // Swap ranks
    const tempRank = provider1.rank;
    provider1.rank = provider2.rank;
    provider2.rank = tempRank;

    // Update files
    const file1Updated = provider1.filePath ? await updateProviderRank(provider1.filePath, provider1.rank) : false;
    const file2Updated = provider2.filePath ? await updateProviderRank(provider2.filePath, provider2.rank) : false;

    // Move provider in array
    currentProviders.splice(index1, 1);
    currentProviders.splice(index2, 0, provider1);
    selectedIndex = newSelectedIndex;

    const status = file1Updated && file2Updated ? '✅' : '⚠️';
    return `${status} Moved ${provider1.name} ${index1 < index2 ? 'down' : 'up'} (rank: ${provider1.rank})`;
  };

  // Set up keypress handling for left/right navigation
  readline.emitKeypressEvents(process.stdin);
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
  }

  // Function to render the current state
  const render = () => {
    // Clear screen and move cursor to top
    process.stdout.write('\x1B[2J\x1B[0f');

    console.log('Use ↑↓ arrows to navigate, ←→ to change rank, Ctrl+C to exit');
    console.log('');

    // Calculate available height for providers
    const terminalHeight = process.stdout.rows || 24; // Default to 24 if not available
    const headerHeight = 4; // Instructions line padding
    const availableHeight = Math.max(5, terminalHeight - headerHeight);

    // Calculate window around selected provider
    const halfWindow = Math.floor(availableHeight / 2);
    let startIndex = Math.max(0, selectedIndex - halfWindow);
    const endIndex = Math.min(currentProviders.length, startIndex + availableHeight);

    // Adjust start index if we're near the end
    if (endIndex - startIndex < availableHeight && startIndex > 0) {
      startIndex = Math.max(0, endIndex - availableHeight);
    }

    // Show the window of providers
    for (let i = startIndex; i < endIndex; i++) {
      const provider = currentProviders[i];
      const isSelected = i === selectedIndex;
      const prefix = isSelected ? '❯ ' : '  ';
      const typeColor = provider.type === 'source' ? '[SOURCE]' : '[EMBED] ';
      const mediaTypes = joinMediaTypes(provider.mediaTypes);
      const line = `${prefix}${typeColor} [${provider.rank}] ${provider.name} ${mediaTypes}`.trim();

      console.log(isSelected ? `\x1b[36m${line}\x1b[0m` : `  ${line}`);
    }

    console.log('');
  };

  // Initial render
  render();

  return new Promise<void>((resolve) => {
    process.stdin.on('keypress', async (str: string, key: readline.Key) => {
      let shouldReRender = false;

      if (key?.name === 'up' && selectedIndex > 0) {
        selectedIndex--;
        shouldReRender = true;
      } else if (key?.name === 'down' && selectedIndex < currentProviders.length - 1) {
        selectedIndex++;
        shouldReRender = true;
      } else if (key?.name === 'left') {
        // Move selected provider down (lower priority)
        if (selectedIndex < currentProviders.length - 1) {
          const message = await swapProviders(selectedIndex, selectedIndex + 1, selectedIndex + 1);
          console.log(`\n${message}`);
          shouldReRender = true;
        }
      } else if (key?.name === 'right') {
        // Move selected provider up (higher priority)
        if (selectedIndex > 0) {
          const message = await swapProviders(selectedIndex, selectedIndex - 1, selectedIndex - 1);
          console.log(`\n${message}`);
          shouldReRender = true;
        }
      } else if (
        key?.name === 'return' ||
        key?.name === 'escape' ||
        key?.name === 'q' ||
        (key?.ctrl && key?.name === 'c')
      ) {
        process.stdin.setRawMode(false);
        process.stdin.pause();
        resolve();
        return;
      }

      if (shouldReRender) {
        render();
      }
    });
  });
}
