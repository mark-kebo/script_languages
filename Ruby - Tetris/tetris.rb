#!/usr/bin/env ruby

require 'io/console'

PLAYFIELD_W = 10
PLAYFIELD_H = 20
PLAYFIELD_X = 30
PLAYFIELD_Y = 1
BORDER_COLOR = :yellow

HELP_X = 58
HELP_Y = 1
HELP_COLOR = :cyan

SCORE_X = 1
SCORE_Y = 2
SCORE_COLOR = :green

NEXT_X = 14
NEXT_Y = 11

GAMEOVER_X = 1
GAMEOVER_Y = PLAYFIELD_H + 3

INITIAL_MOVE_DOWN_DELAY = 1.0
DELAY_FACTOR = 0.8
LEVEL_UP = 20

NEXT_EMPTY_CELL = "  "
PLAYFIELD_EMPTY_CELL = " ."
FILLED_CELL = "[]"

class TetrisScreen
    @@color = {
        :red => 1,
        :green => 2,
        :yellow => 3,
        :blue => 4,
        :fuchsia => 5,
        :cyan => 6,
        :white => 7
    }

    def initialize
        @s = ""
        @use_color = true
    end

    def print(s)
        @s += s
    end

    def xyprint(x, y, s)
        @s += "\e[#{y};#{x}H#{s}"
    end

    def show_cursor()
        @s += "\e[?25h"
    end

    def hide_cursor()
        @s += "\e[?25l"
    end

    def set_fg(c)
        @use_color && @s += "\e[3#{@@color[c]}m"
    end

    def set_bg(c)
        @use_color && @s += "\e[4#{@@color[c]}m"
    end

    def reset_colors()
        @s += "\e[0m"
    end

    def set_bold()
        @s += "\e[1m"
    end

    def clear_screen()
        @s += "\e[2J"
    end

    def flush()
        Kernel::print @s
        @s = ""
    end

    def get_random_color()
        @@color.keys.sample
    end

    def toggle_color()
        @use_color ^= true
    end
end

class TetrisScreenItem
    attr_accessor :visible

    def initialize(screen)
        @visible = true
        @screen = screen
    end

    def show()
        draw(true) if @visible
    end

    def hide()
        draw(false) if @visible
    end

    def toggle()
        @visible ^= true
        draw(@visible)
    end
end

class TetrisHelp < TetrisScreenItem
    def initialize(screen)
        super(screen)
        @color = HELP_COLOR
        @text = [
            "  Use cursor keys",
            "       or",
            "    s: rotate",
            "a: left,  d: right",
            "    space: drop",
            "      q: quit",
            "  c: toggle color",
            "n: toggle show next",
            "h: toggle this help"
        ]
    end

    def draw(visible)
        @screen.set_bold()
        @screen.set_fg(@color)
        @text.each_with_index do |s, i|
            @screen.xyprint(HELP_X, HELP_Y + i, visible ? s : ' ' * s.length)
        end
        @screen.reset_colors()
    end
end

class TetrisPlayField
    def initialize(screen)
        @screen = screen
        @cells = Array.new(PLAYFIELD_H) { Array.new(PLAYFIELD_W) }
    end

    def show()
        @cells.each_with_index do |row, y|
            @screen.xyprint(PLAYFIELD_X, PLAYFIELD_Y + y, "")
            row.each do |cell|
                if cell == nil
                    @screen.print(PLAYFIELD_EMPTY_CELL)
                else
                    @screen.set_fg(cell)
                    @screen.set_bg(cell)
                    @screen.print(FILLED_CELL)
                    @screen.reset_colors()
                end
            end
        end
    end

    def flatten_piece(piece)
        piece.get_cells().each do |x, y|
            @cells[y][x] = piece.color
        end
    end

    def process_complete_lines()
        @cells.select! {|row| row.include?(nil) }
        complete_lines = PLAYFIELD_H - @cells.size
        complete_lines.times { @cells.unshift(Array.new(PLAYFIELD_W)) }
        return complete_lines
    end

    def draw_border()
        @screen.set_bold()
        @screen.set_fg(BORDER_COLOR)
        (0..PLAYFIELD_H).map {|y| y + PLAYFIELD_Y}.each do |y|
            # 2 because border is 2 characters thick
            @screen.xyprint(PLAYFIELD_X - 2, y, "<|")
            # 2 because each cell on play field is 2 characters wide
            @screen.xyprint(PLAYFIELD_X + PLAYFIELD_W * 2, y, "|>")
        end

        ['==', '\/'].each_with_index do |s, y|
            @screen.xyprint(PLAYFIELD_X, PLAYFIELD_Y + PLAYFIELD_H + y, s * PLAYFIELD_W)
        end
        @screen.reset_colors()
    end

    def position_ok?(piece, position = nil)
        piece.get_cells(position).all? do |x, y|
            x.between?(0, PLAYFIELD_W - 1) && y.between?(0, PLAYFIELD_H - 1) && @cells[y][x].nil?
        end
    end
end

class TetrisPiece < TetrisScreenItem
    attr_accessor :empty_cell, :origin, :position
    attr_reader :color

    @@piece_data = [
        %w(1256), # square
        %w(159d 4567), # line
        %w(4512 0459), # s
        %w(0156 1548), # z
        %w(159a 8456 0159 2654), # l
        %w(1598 0456 2159 a654), # inverted l
        %w(1456 1596 4569 4159)  # t
    ]

    def initialize(screen, origin, visible)
        super(screen)
        @origin = origin
        @visible = visible
        @color = @screen.get_random_color()
        @data = @@piece_data.sample
        @symmetry = @data.size
        @position = 0, 0, rand(@symmetry)
        @empty_cell = NEXT_EMPTY_CELL
    end

    def get_cells(new_position = nil)
        x, y, z = new_position || @position
        data = @data[z]
        data.split('').map {|c| i = c.hex; [x + (i & 3), y + ((i >> 2) & 3)]}
    end

    def draw(visible)
        if visible
            @screen.set_fg(@color)
            @screen.set_bg(@color)
        end
        ox, oy = @origin
        get_cells().each do |x, y|
            @screen.xyprint(ox + x * 2, oy + y, visible ? FILLED_CELL : @empty_cell)
        end
        @screen.reset_colors()
    end

    def new_position(dx, dy, dz)
        x, y, z = @position
        [x + dx, y + dy, (z + dz) % @symmetry]
    end
end

class TetrisScore
    def initialize(screen)
        @screen = screen
        @score = 0
        @level = 1
        @lines_completed = 0
    end

    def update(complete_lines)
        @lines_completed += complete_lines
        @score += (complete_lines * complete_lines)
        if @score > LEVEL_UP * @level
            @level += 1
            TetrisInputProcessor.decrease_move_down_delay()
        end
        show()
    end

    def show()
        @screen.set_bold()
        @screen.set_fg(SCORE_COLOR)
        @screen.xyprint(SCORE_X, SCORE_Y,     "Lines completed: #{@lines_completed}")
        @screen.xyprint(SCORE_X, SCORE_Y + 1, "Level:           #{@level}")
        @screen.xyprint(SCORE_X, SCORE_Y + 2, "Score:           #{@score}")
        @screen.reset_colors()
    end
end

class TetrisController
    attr_reader :running

    def initialize
        @screen = TetrisScreen.new
        @next_piece_visible = true
        @running = true
        @help = TetrisHelp.new(@screen)
        @score = TetrisScore.new(@screen)
        @play_field = TetrisPlayField.new(@screen)
        get_next_piece()
        get_current_piece()
        redraw_screen()
        @screen.flush()
    end

    def get_current_piece()
        @next_piece.hide()
        @current_piece = @next_piece
        @current_piece.position = [(PLAYFIELD_W - 4) / 2, 0, @current_piece.position[2]]
        if ! @play_field.position_ok?(@current_piece)
            process(:cmd_quit)
            return
        end
        @current_piece.visible = true
        @current_piece.empty_cell = PLAYFIELD_EMPTY_CELL
        @current_piece.origin = [PLAYFIELD_X, PLAYFIELD_Y]
        @current_piece.show()
        get_next_piece()
    end

    def get_next_piece()
        @next_piece = TetrisPiece.new(@screen, [NEXT_X, NEXT_Y], @next_piece_visible)
        @next_piece.show()
    end

    def redraw_screen()
        @screen.clear_screen()
        @screen.hide_cursor()
        @play_field.draw_border()
        [@help, @play_field, @score, @next_piece, @current_piece].each {|o| o.show()}
    end

    def cmd_quit
        @running = false
        @screen.xyprint(GAMEOVER_X, GAMEOVER_Y, "Game over!")
        @screen.xyprint(GAMEOVER_X, GAMEOVER_Y + 1, "")
        @screen.show_cursor()
    end

    def process_fallen_piece()
        @play_field.flatten_piece(@current_piece)
        complete_lines = @play_field.process_complete_lines()
        if complete_lines > 0
            @score.update(complete_lines)
            @play_field.show()
        end
    end

    def move(dx, dy, dz)
        new_position = @current_piece.new_position(dx, dy, dz)
        if @play_field.position_ok?(@current_piece, new_position)
            @current_piece.hide()
            @current_piece.position = new_position
            @current_piece.show()
            return true
        end
        dy == 0
    end

    def cmd_right
        move(1, 0, 0)
    end

    def cmd_left
        move(-1, 0, 0)
    end

    def cmd_rotate
        move(0, 0, 1)
    end

    def cmd_down
        return true if move(0, 1, 0)
        process_fallen_piece()
        get_current_piece()
        false
    end

    def cmd_drop
        while cmd_down()
        end
    end

    def toggle_help
        @help.toggle()
    end

    def toggle_next
        @next_piece_visible ^= true
        @next_piece.toggle()
    end

    def toggle_color
        @screen.toggle_color()
        redraw_screen()
    end

    def process(cmd)
        send(cmd)
        @screen.flush()
    end
end

class TetrisInputProcessor
    @@move_down_delay = INITIAL_MOVE_DOWN_DELAY

    def self.decrease_move_down_delay()
        @@move_down_delay *= DELAY_FACTOR
    end

    def initialize
        @commands = {
            "\u0003" => :cmd_quit,
            "q" => :cmd_quit,
            "C" => :cmd_right,
            "d" => :cmd_right,
            "D" => :cmd_left,
            "a" => :cmd_left,
            "A" => :cmd_rotate,
            "s" => :cmd_rotate,
            " " => :cmd_drop,
            "h" => :toggle_help,
            "n" => :toggle_next,
            "c" => :toggle_color
        }
        @controller = TetrisController.new
    end

    def run()
        begin
            STDIN.echo = false
            STDIN.raw!
            key = %w(x x x)
            last_move_down_time = Time.now.to_f
            while @controller.running
                now = Time.now.to_f
                select_timeout = @@move_down_delay - (now - last_move_down_time)
                if select_timeout < 0
                    last_move_down_time = now
                    select_timeout = @@move_down_delay
                end
                a = select([STDIN], [], [], select_timeout)
                cmd = :cmd_down
                if a
                    key.unshift(a[0][0].getc()).pop
                    if key[1..2] == ["[", "\e"]
                        cmd = @commands[key[0]]
                    else
                        cmd = @commands[key[0].downcase()]
                    end
                end
                @controller.process(cmd) if cmd
            end
        ensure
            STDIN.echo = true
            STDIN.cooked!
        end
    end
end

TetrisInputProcessor.new.run
