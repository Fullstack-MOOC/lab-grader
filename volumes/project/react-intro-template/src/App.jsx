import React, { useState } from 'react';
import SearchBar from './components/search_bar';

function App() {
  const [searchTerm, setSearchTerm] = useState('');

  const handleSearchChange = term => {
    setSearchTerm(term);
  };

  return (
    <div className='App'>
      <h1>React App</h1>
      <SearchBar onSearchChange={handleSearchChange} />
      <div>Search term: {searchTerm}</div>
    </div>
  );
}

export default App;
