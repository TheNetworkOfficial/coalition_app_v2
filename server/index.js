const express = require('express');

const app = express();
const PORT = process.env.PORT || 4000;

app.use(express.json());

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

const generateId = (prefix) => `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

app.post('/api/uploads/create', (req, res) => {
  const postId = generateId('post');
  const uploadUrl = `https://uploads.example.com/${postId}`;

  res.json({ uploadUrl, postId });
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
