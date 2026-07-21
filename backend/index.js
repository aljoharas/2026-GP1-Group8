const express = require('express');
const cors = require('cors');
require('dotenv').config();

const authRoutes  = require('./routes/auth');
const userRoutes  = require('./routes/users');
const gameRoutes  = require('./routes/games');
const homeRoutes = require('./routes/home');
const listRoutes = require('./routes/lists');


const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Routes
app.use('/auth',  authRoutes);
app.use('/users', userRoutes);
app.use('/games', gameRoutes);
app.use('/home', homeRoutes);
app.use('/lists', listRoutes);

// Health check
app.get('/', (req, res) => {
  res.json({ message: 'Loadout API is running' });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});