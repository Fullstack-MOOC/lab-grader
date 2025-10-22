import React, { useState } from 'react'
import './App.css'

function App() {
  const [count, setCount] = useState(0)
  const [message, setMessage] = useState('Hello Coursera!')
  const [items, setItems] = useState(['Item 1', 'Item 2', 'Item 3'])

  const handleIncrement = () => {
    setCount(count + 1)
  }

  const handleDecrement = () => {
    setCount(count - 1)
  }

  const handleReset = () => {
    setCount(0)
  }

  const handleMessageChange = (e) => {
    setMessage(e.target.value)
  }

  const addItem = () => {
    const newItem = `Item ${items.length + 1}`
    setItems([...items, newItem])
  }

  const removeItem = (index) => {
    setItems(items.filter((_, i) => i !== index))
  }

  return (
    <div className="App">
      <header className="App-header">
        <h1 data-testid="app-title">Coursera React Lab</h1>
        
        <div className="counter-section">
          <h2>Counter Component</h2>
          <div className="counter-display">
            <span data-testid="counter-value">{count}</span>
          </div>
          <div className="counter-buttons">
            <button data-testid="increment-btn" onClick={handleIncrement}>
              Increment
            </button>
            <button data-testid="decrement-btn" onClick={handleDecrement}>
              Decrement
            </button>
            <button data-testid="reset-btn" onClick={handleReset}>
              Reset
            </button>
          </div>
        </div>

        <div className="message-section">
          <h2>Message Component</h2>
          <input
            data-testid="message-input"
            type="text"
            value={message}
            onChange={handleMessageChange}
            placeholder="Enter a message"
          />
          <p data-testid="message-display">{message}</p>
        </div>

        <div className="list-section">
          <h2>List Component</h2>
          <button data-testid="add-item-btn" onClick={addItem}>
            Add Item
          </button>
          <ul data-testid="item-list">
            {items.map((item, index) => (
              <li key={index} data-testid={`item-${index}`}>
                {item}
                <button 
                  data-testid={`remove-item-${index}`}
                  onClick={() => removeItem(index)}
                >
                  Remove
                </button>
              </li>
            ))}
          </ul>
        </div>
      </header>
    </div>
  )
}

export default App
