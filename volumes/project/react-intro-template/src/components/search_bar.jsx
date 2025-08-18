import React from 'react';

const SearchBar = ({ onSearchChange }) => {
  const handleInputChange = (e) => {
    onSearchChange(e.target.value);
  };

  return (
    <div id="search-bar">
      <input type="text" onChange={handleInputChange} />
    </div>
  );
};

export default SearchBar;