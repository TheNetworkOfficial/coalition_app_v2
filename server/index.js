const express = require('express');

const app = express();
const PORT = process.env.PORT || 4000;

app.use(express.json());

const SIMPLE_UPLOAD_LIMIT_BYTES = (() => {
  const raw = Number.parseInt(
    process.env.CLOUDFLARE_STREAM_SIMPLE_UPLOAD_LIMIT_BYTES ?? '',
    10,
  );
  return Number.isFinite(raw) && raw > 0 ? raw : 200 * 1024 * 1024;
})();

const DEFAULT_MAX_DURATION_SECONDS = (() => {
  const raw = Number.parseInt(
    process.env.CLOUDFLARE_STREAM_MAX_DURATION_SECONDS ?? '',
    10,
  );
  return Number.isFinite(raw) && raw > 0 ? raw : 3600;
})();

const DEFAULT_EXPIRY_SECONDS = (() => {
  const raw = Number.parseInt(
    process.env.CLOUDFLARE_STREAM_UPLOAD_EXPIRY_SECONDS ?? '',
    10,
  );
  return Number.isFinite(raw) && raw > 0 ? raw : 3600;
})();

const ALLOWED_ORIGINS = (process.env.CLOUDFLARE_STREAM_ALLOWED_ORIGINS
  ? process.env.CLOUDFLARE_STREAM_ALLOWED_ORIGINS.split(',')
      .map((origin) => origin.trim())
      .filter(Boolean)
  : undefined);

const REQUIRE_SIGNED_URLS = /^true$/i.test(
  process.env.CLOUDFLARE_STREAM_REQUIRE_SIGNED_URLS ?? '',
);

const CLOUDFLARE_ACCOUNT_ID = process.env.CLOUDFLARE_ACCOUNT_ID;
const CLOUDFLARE_API_TOKEN = process.env.CLOUDFLARE_API_TOKEN;

const ensureCloudflareConfigured = () => {
  if (!CLOUDFLARE_ACCOUNT_ID || !CLOUDFLARE_API_TOKEN) {
    throw new Error(
      'Cloudflare Stream is not configured. Set CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN.',
    );
  }
};

const toPositiveInteger = (value, fallback) => {
  if (value == null) {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

const futureExpiryIsoString = (secondsFromNow) =>
  new Date(Date.now() + secondsFromNow * 1000).toISOString();

const encodeMetadataHeader = (metadata) => {
  const entries = Object.entries(metadata)
    .filter(([, value]) => value != null && `${value}`.length > 0)
    .map(([key, value]) => `${key} ${Buffer.from(String(value)).toString('base64')}`);

  return entries.length > 0 ? entries.join(',') : undefined;
};

const extractUidFromLocation = (location) => {
  if (typeof location !== 'string') {
    return undefined;
  }
  try {
    const url = new URL(location);
    const segments = url.pathname.split('/').filter(Boolean);
    return segments.length > 0 ? segments[segments.length - 1] : undefined;
  } catch (error) {
    const segments = location.split('/').filter(Boolean);
    return segments.length > 0 ? segments[segments.length - 1] : undefined;
  }
};

const requestCloudflareDirectUpload = async ({
  maxDurationSeconds,
  expiry,
  creatorId,
  fileName,
}) => {
  ensureCloudflareConfigured();

  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream/direct_upload`;
  const body = {
    maxDurationSeconds,
    expiry,
    requireSignedURLs: REQUIRE_SIGNED_URLS || undefined,
    allowedOrigins: ALLOWED_ORIGINS && ALLOWED_ORIGINS.length > 0 ? ALLOWED_ORIGINS : undefined,
    creator: creatorId ? { id: creatorId } : undefined,
  };

  Object.keys(body).forEach((key) => {
    if (body[key] == null) {
      delete body[key];
    }
  });

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  let data;
  try {
    data = await response.json();
  } catch (error) {
    if (!response.ok) {
      throw new Error(
        `Failed to parse Cloudflare response (${response.status} ${response.statusText}).`,
      );
    }
    throw error;
  }

  if (!response.ok || !data?.success) {
    const errors = Array.isArray(data?.errors) ? data.errors : [];
    const message = errors.length > 0 ? JSON.stringify(errors) : response.statusText;
    throw new Error(`Cloudflare direct upload creation failed: ${message}`);
  }

  if (!data?.result?.uploadURL || !data?.result?.uid) {
    throw new Error('Cloudflare direct upload response missing uploadURL or uid');
  }

  return {
    uploadUrl: data.result.uploadURL,
    uid: data.result.uid,
  };
};

const requestCloudflareTusUpload = async ({
  fileSize,
  metadataHeader,
  creatorId,
}) => {
  ensureCloudflareConfigured();

  const endpoint = `https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/stream?direct_user=true`;
  const headers = {
    Authorization: `Bearer ${CLOUDFLARE_API_TOKEN}`,
    'Tus-Resumable': '1.0.0',
    'Upload-Length': String(fileSize),
  };

  if (metadataHeader) {
    headers['Upload-Metadata'] = metadataHeader;
  }

  if (creatorId) {
    headers['Upload-Creator'] = creatorId;
  }

  const response = await fetch(endpoint, {
    method: 'POST',
    headers,
  });

  if (!response.ok) {
    const text = await response.text().catch(() => undefined);
    throw new Error(
      `Cloudflare tus upload creation failed (${response.status} ${response.statusText})${
        text ? `: ${text}` : ''
      }`,
    );
  }

  const location = response.headers.get('Location') ?? response.headers.get('location');
  if (!location) {
    throw new Error('Cloudflare tus upload response missing Location header');
  }

  const uid = response.headers.get('stream-media-id') ?? extractUidFromLocation(location);
  if (!uid) {
    throw new Error('Unable to determine Cloudflare stream UID for tus upload');
  }

  return {
    uploadUrl: location,
    uid,
  };
};

const feedPosts = Array.from({ length: 15 }).map((_, index) => ({
  id: `feed-${index + 1}`,
  author: index % 2 === 0 ? 'Taylor' : 'Morgan',
  createdAt: new Date(Date.now() - index * 3600_000).toISOString(),
  status: index % 3 === 0 ? 'processing' : 'published',
  mediaUrl: `https://example.com/media/feed-${index + 1}.jpg`,
  description: `Feed post number ${index + 1}`,
}));

const myPosts = Array.from({ length: 8 }).map((_, index) => ({
  id: `me-${index + 1}`,
  createdAt: new Date(Date.now() - index * 7200_000).toISOString(),
  status: index % 4 === 0 ? 'processing' : 'published',
  mediaUrl: `https://example.com/media/me-${index + 1}.jpg`,
  description: `My post number ${index + 1}`,
}));

const paginate = (items, page = 1, pageSize = 5) => {
  const start = (page - 1) * pageSize;
  const data = items.slice(start, start + pageSize);
  return {
    page,
    pageSize,
    total: items.length,
    totalPages: Math.ceil(items.length / pageSize),
    data,
  };
};

app.post('/api/uploads/create', async (req, res) => {
  try {
    const { type, fileSize, fileName, contentType, maxDurationSeconds, creatorId } = req.body ?? {};

    if (typeof type !== 'string' || !type) {
      return res.status(400).json({ error: 'type is required' });
    }

    const size = Number(fileSize);
    if (!Number.isFinite(size) || size <= 0) {
      return res.status(400).json({ error: 'fileSize must be a positive number' });
    }

    const resolvedMaxDurationSeconds = toPositiveInteger(
      maxDurationSeconds,
      DEFAULT_MAX_DURATION_SECONDS,
    );
    const expirySeconds = DEFAULT_EXPIRY_SECONDS;
    const expiry = futureExpiryIsoString(expirySeconds);

    const cleanedFileName = typeof fileName === 'string' && fileName.trim().length > 0
      ? fileName.trim()
      : undefined;
    const cleanedContentType = typeof contentType === 'string' && contentType.trim().length > 0
      ? contentType.trim()
      : undefined;

    if (size <= SIMPLE_UPLOAD_LIMIT_BYTES) {
      const directUpload = await requestCloudflareDirectUpload({
        maxDurationSeconds: resolvedMaxDurationSeconds,
        expiry,
        creatorId,
        fileName: cleanedFileName,
      });

      return res.json({
        postId: directUpload.uid,
        uploadUrl: directUpload.uploadUrl,
        requiresMultipart: true,
        method: 'POST',
        fileFieldName: 'file',
        taskId: directUpload.uid,
      });
    }

    const metadataHeader = encodeMetadataHeader({
      name: cleanedFileName,
      filetype: cleanedContentType,
      maxDurationSeconds: String(resolvedMaxDurationSeconds),
      expiry,
    });

    const tusUpload = await requestCloudflareTusUpload({
      fileSize: size,
      metadataHeader,
      creatorId,
    });

    return res.json({
      postId: tusUpload.uid,
      uploadUrl: tusUpload.uploadUrl,
      requiresMultipart: false,
      method: 'PATCH',
      headers: {
        'Tus-Resumable': '1.0.0',
        'Upload-Offset': '0',
      },
      contentType: 'application/offset+octet-stream',
      taskId: tusUpload.uid,
      tus: {
        uploadLength: size,
        metadata: metadataHeader,
      },
    });
  } catch (error) {
    console.error('Failed to create upload URL', error);
    res.status(500).json({
      error: 'Failed to create upload URL',
      details: error instanceof Error ? error.message : undefined,
    });
  }
});

app.post('/api/posts/metadata', (req, res) => {
  res.json({ ok: true });
});

app.get('/api/feed', (req, res) => {
  const page = parseInt(req.query.page, 10) || 1;
  const pageSize = parseInt(req.query.pageSize, 10) || 5;

  res.json(paginate(feedPosts, page, pageSize));
});

app.get('/api/me/posts', (req, res) => {
  const page = parseInt(req.query.page, 10) || 1;
  const pageSize = parseInt(req.query.pageSize, 10) || 5;

  res.json(paginate(myPosts, page, pageSize));
});

app.listen(PORT, () => {
  console.log(`Mock backend listening on http://localhost:${PORT}`);
});
